FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        awscli \
        ca-certificates \
        openjdk-17-jre-headless \
    && rm -rf /var/lib/apt/lists/*

CMD ["/bin/sh"]
