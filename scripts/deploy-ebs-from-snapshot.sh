#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  deploy-ebs-from-snapshot.sh [options]

Creates a pre-deploy snapshot from the single running ECS service task volume,
waits for completion, then runs terraform apply with ebs_snapshot_id set to the
new snapshot.

Options:
  --cluster NAME            ECS cluster name. Defaults to terraform output ecs_cluster_name.
  --service NAME            ECS service name. Defaults to terraform output ecs_service_name.
  --region NAME             AWS region. Defaults to AWS_REGION or AWS_DEFAULT_REGION.
  --tfvars-file PATH        Terraform tfvars file to pass to apply. Can be repeated.
  --quiesce-command CMD     Optional shell command to run before creating the snapshot.
  --snapshot-tag KEY=VALUE  Extra tag to apply to the snapshot. Can be repeated.
  --auto-approve            Pass -auto-approve to terraform apply.
  --skip-apply              Create and wait for the snapshot, but do not run terraform apply.
  -h, --help                Show this help text.

Examples:
  ./scripts/deploy-ebs-from-snapshot.sh --tfvars-file terraform-dev.tfvars
  ./scripts/deploy-ebs-from-snapshot.sh --cluster delphix-masking-dev-cluster --service delphix-masking-dev-service
  ./scripts/deploy-ebs-from-snapshot.sh --tfvars-file terraform-dev.tfvars --quiesce-command "./bin/quiesce-masking.sh"
EOF
}

require_command() {
  local command_name=$1
  if ! command -v "$command_name" >/dev/null 2>&1; then
    echo "Missing required command: $command_name" >&2
    exit 1
  fi
}

terraform_output() {
  local output_name=$1
  terraform output -raw "$output_name" 2>/dev/null || true
}

cluster_name=""
service_name=""
aws_region="${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
quiesce_command=""
skip_apply=false
auto_approve=false
tfvars_files=()
snapshot_tags=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cluster)
      cluster_name=$2
      shift 2
      ;;
    --service)
      service_name=$2
      shift 2
      ;;
    --region)
      aws_region=$2
      shift 2
      ;;
    --tfvars-file|--var-file)
      tfvars_files+=("$2")
      shift 2
      ;;
    --quiesce-command)
      quiesce_command=$2
      shift 2
      ;;
    --snapshot-tag)
      snapshot_tags+=("$2")
      shift 2
      ;;
    --auto-approve)
      auto_approve=true
      shift
      ;;
    --skip-apply)
      skip_apply=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

require_command aws
require_command jq
require_command terraform

if [[ -z "$cluster_name" ]]; then
  cluster_name=$(terraform_output ecs_cluster_name)
fi

if [[ -z "$service_name" ]]; then
  service_name=$(terraform_output ecs_service_name)
fi

if [[ -z "$cluster_name" || -z "$service_name" ]]; then
  echo "Unable to determine ECS cluster/service. Pass --cluster and --service or ensure terraform outputs exist." >&2
  exit 1
fi

aws_args=()
if [[ -n "$aws_region" ]]; then
  aws_args+=(--region "$aws_region")
fi

running_tasks_json=$(aws "${aws_args[@]}" ecs list-tasks \
  --cluster "$cluster_name" \
  --service-name "$service_name" \
  --desired-status RUNNING \
  --output json)

running_task_count=$(jq -r '.taskArns | length' <<<"$running_tasks_json")
if [[ "$running_task_count" -ne 1 ]]; then
  echo "Expected exactly one running task for EBS mode, found $running_task_count." >&2
  exit 1
fi

task_arn=$(jq -r '.taskArns[0]' <<<"$running_tasks_json")
task_description_json=$(aws "${aws_args[@]}" ecs describe-tasks \
  --cluster "$cluster_name" \
  --tasks "$task_arn" \
  --output json)

volume_id=$(jq -r '
  .tasks[0].attachments[]?
  | select(.type == "AmazonElasticBlockStorage")
  | .details[]?
  | select(.name == "volumeId")
  | .value
' <<<"$task_description_json")

if [[ -z "$volume_id" || "$volume_id" == "null" ]]; then
  echo "Could not locate the attached EBS volume ID from ECS task attachments." >&2
  exit 1
fi

task_definition_arn=$(jq -r '.tasks[0].taskDefinitionArn' <<<"$task_description_json")
timestamp_utc=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
snapshot_name="${service_name}-predeploy-${timestamp_utc}"
snapshot_description="Pre-deploy snapshot for ${service_name} from ${volume_id} at ${timestamp_utc}"

if [[ -n "$quiesce_command" ]]; then
  echo "Running quiesce command before snapshot creation..."
  /bin/bash -lc "$quiesce_command"
fi

extra_tags_json="[]"
for tag_entry in "${snapshot_tags[@]}"; do
  if [[ "$tag_entry" != *=* ]]; then
    echo "Invalid --snapshot-tag value: $tag_entry" >&2
    exit 1
  fi

  tag_key=${tag_entry%%=*}
  tag_value=${tag_entry#*=}
  extra_tags_json=$(jq \
    --arg key "$tag_key" \
    --arg value "$tag_value" \
    '. + [{Key: $key, Value: $value}]' <<<"$extra_tags_json")
done

tag_spec_file=$(mktemp)
cleanup() {
  rm -f "$tag_spec_file"
}
trap cleanup EXIT

jq -n \
  --arg snapshot_name "$snapshot_name" \
  --arg cluster_name "$cluster_name" \
  --arg service_name "$service_name" \
  --arg volume_id "$volume_id" \
  --arg task_arn "$task_arn" \
  --arg task_definition_arn "$task_definition_arn" \
  --arg timestamp_utc "$timestamp_utc" \
  --argjson extra_tags "$extra_tags_json" \
  '[
    {
      ResourceType: "snapshot",
      Tags: (
        [
          {Key: "Name", Value: $snapshot_name},
          {Key: "CreatedBy", Value: "deploy-ebs-from-snapshot.sh"},
          {Key: "CreatedAt", Value: $timestamp_utc},
          {Key: "SnapshotRole", Value: "predeploy"},
          {Key: "SourceCluster", Value: $cluster_name},
          {Key: "SourceService", Value: $service_name},
          {Key: "SourceTaskArn", Value: $task_arn},
          {Key: "SourceTaskDefinitionArn", Value: $task_definition_arn},
          {Key: "SourceVolumeId", Value: $volume_id}
        ] + $extra_tags
      )
    }
  ]' >"$tag_spec_file"

echo "Creating snapshot from volume $volume_id..."
snapshot_id=$(aws "${aws_args[@]}" ec2 create-snapshot \
  --volume-id "$volume_id" \
  --description "$snapshot_description" \
  --tag-specifications "file://$tag_spec_file" \
  --query 'SnapshotId' \
  --output text)

echo "Created snapshot $snapshot_id. Waiting for completion..."
aws "${aws_args[@]}" ec2 wait snapshot-completed --snapshot-ids "$snapshot_id"
echo "Snapshot $snapshot_id completed."

if [[ "$skip_apply" == "true" ]]; then
  echo "Skipping terraform apply."
  echo "Next step: terraform apply -var=\"ebs_snapshot_id=$snapshot_id\""
  exit 0
fi

terraform_apply_args=("apply")
for tfvars_file in "${tfvars_files[@]}"; do
  terraform_apply_args+=("-var-file=$tfvars_file")
done
terraform_apply_args+=("-var=ebs_snapshot_id=$snapshot_id")

if [[ "$auto_approve" == "true" ]]; then
  terraform_apply_args+=("-auto-approve")
fi

echo "Running terraform ${terraform_apply_args[*]}"
terraform "${terraform_apply_args[@]}"

echo "Waiting for ECS service to become stable..."
aws "${aws_args[@]}" ecs wait services-stable --cluster "$cluster_name" --services "$service_name"

cat <<EOF
Deployment completed.
Snapshot used: $snapshot_id
To roll back, redeploy with the previous known-good snapshot ID:
  terraform apply -var="ebs_snapshot_id=<previous-snapshot-id>"
EOF
