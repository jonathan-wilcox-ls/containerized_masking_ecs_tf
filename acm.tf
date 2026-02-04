resource "aws_acm_certificate" "this" {
  count = var.create_acm_certificate ? 1 : 0

  domain_name       = var.acm_domain_name
  validation_method = "DNS"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-acm" })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "acm_validation" {
  for_each = var.create_acm_certificate ? {
    for dvo in aws_acm_certificate.this[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  } : {}

  zone_id = var.route53_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "this" {
  count = var.create_acm_certificate ? 1 : 0

  certificate_arn         = aws_acm_certificate.this[0].arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}

resource "aws_route53_record" "service_alias" {
  count = var.create_acm_certificate ? 1 : 0

  zone_id = var.route53_zone_id
  name    = var.acm_domain_name
  type    = "A"

  alias {
    name                   = aws_lb.this.dns_name
    zone_id                = aws_lb.this.zone_id
    evaluate_target_health = true
  }
}
