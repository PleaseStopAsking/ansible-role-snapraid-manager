#!/usr/bin/env bash
set -euo pipefail

base_image="${1:-debian:13}"
test_scope="${2:-all}"
if [[ "$test_scope" != all && "$test_scope" != core ]]; then
    printf 'Usage: bash tests/integration.sh [image] [all|core]\n' >&2
    exit 2
fi
if [[ "$test_scope" = all && "$(docker info --format '{{.Architecture}}')" != x86_64 ]]; then
    printf 'Full daemon integration tests require a native amd64 Docker host. Use core mode for emulated CLI tests.\n' >&2
    exit 2
fi
image_name="snapraid-manager-test:${base_image//:/-}"
container_name="snapraid-manager-test-$$"
log_file="$(mktemp)"
trap 'docker rm -f "$container_name" >/dev/null 2>&1 || true; rm -f "$log_file"' EXIT

docker build --platform linux/amd64 --build-arg "BASE_IMAGE=$base_image" \
    -t "$image_name" -f tests/Dockerfile .
docker run -d --platform linux/amd64 --name "$container_name" \
    --privileged --cgroupns=host \
    --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
    --tmpfs /mnt/data1 --tmpfs /mnt/data2 \
    --tmpfs /mnt/parity1 --tmpfs /mnt/parity2 \
    -v /sys/fs/cgroup:/sys/fs/cgroup:rw "$image_name"
playbook_args=(-i "$container_name," -e ansible_connection=community.docker.docker \
    -e ansible_python_interpreter=/usr/bin/python3)

ansible-playbook "${playbook_args[@]}" tests/converge.yml
ansible-playbook "${playbook_args[@]}" tests/converge.yml | tee "$log_file"
grep -Eq 'changed=0[[:space:]]+unreachable=0[[:space:]]+failed=0' "$log_file"

ansible-playbook "${playbook_args[@]}" tests/healthchecks.yml -e '{"snapraid_manager_healthchecks_enabled": false}'
ansible-playbook "${playbook_args[@]}" tests/healthchecks.yml
ansible-playbook "${playbook_args[@]}" tests/healthchecks.yml | tee "$log_file"
grep -Eq 'changed=0[[:space:]]+unreachable=0[[:space:]]+failed=0' "$log_file"
ansible-playbook "${playbook_args[@]}" tests/healthchecks.yml -e '{"snapraid_manager_healthchecks_include_report": true}'
ansible-playbook "${playbook_args[@]}" tests/healthchecks.yml -e '{"snapraid_manager_healthchecks_include_report": true}' | tee "$log_file"
grep -Eq 'changed=0[[:space:]]+unreachable=0[[:space:]]+failed=0' "$log_file"
ansible-playbook "${playbook_args[@]}" tests/healthchecks.yml
ansible-playbook "${playbook_args[@]}" tests/healthchecks.yml -e '{"snapraid_manager_healthchecks_include_report": true}'
ansible-playbook "${playbook_args[@]}" tests/healthchecks.yml -e '{"snapraid_manager_healthchecks_enabled": false, "snapraid_manager_healthchecks_include_report": true}'
ansible-playbook "${playbook_args[@]}" tests/healthchecks.yml -e '{"snapraid_manager_healthchecks_enabled": false}'

if [[ "$test_scope" = core ]]; then
    exit 0
fi

ansible-playbook "${playbook_args[@]}" tests/converge.yml -e snapraid_manager_test_daemon=true
ansible-playbook "${playbook_args[@]}" tests/converge.yml -e snapraid_manager_test_daemon=true | tee "$log_file"
grep -Eq 'changed=0[[:space:]]+unreachable=0[[:space:]]+failed=0' "$log_file"

ansible-playbook "${playbook_args[@]}" tests/verify.yml
