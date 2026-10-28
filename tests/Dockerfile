ARG BASE_IMAGE=debian:13
FROM ${BASE_IMAGE}
ENV container=docker
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  systemd systemd-sysv python3 python3-apt ca-certificates curl util-linux \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*
STOPSIGNAL SIGRTMIN+3
CMD ["/sbin/init"]
