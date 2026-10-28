# Ansible Role: SnapRAID Manager

An Ansible role that installs and configures SnapRAID with optional [SnapRAID Daemon](https://github.com/amadvance/snapraid-daemon)
integration.

## Dependencies

- Target platforms: Debian 12/13 and Ubuntu 24.04/26.04, amd64.
- ansible-core 2.19 or newer
- Systemd is required only when daemon integration is enabled.
- Existing storage mounts and directories. The role never formats, mounts, or creates storage disks.

## Example Playbook

```yaml
- name: Configure SnapRAID
  hosts: storage
  become: true
  roles:
    - role: ansible-role-snapraid-manager
      vars:
        snapraid_manager_data_disks:
          - name: d1
            path: /mnt/data1
          - name: d2
            path: /mnt/data2
        snapraid_manager_parity_disks:
          - level: 1
            path: /mnt/parity1/snapraid.parity
        snapraid_manager_content_files:
          - /var/snapraid.content
          - /mnt/data1/.snapraid.content
```

## Role Variables

Available variables are listed below, along with default values (see defaults/main.yml):

| Variable | Default | Purpose |
| --- | --- | --- |
| `snapraid_manager_install` | `true` | Install the pinned CLI package; disable for an externally installed CLI. |
| `snapraid_manager_version` | `"15.1"` | Upstream CLI version. |
| `snapraid_manager_package_url` | Upstream release asset | Override for an internal mirror. |
| `snapraid_manager_package_checksum` | Pinned SHA-256 | Must match the selected package, including version overrides. |
| `snapraid_manager_binary` | `/usr/bin/snapraid` | Explicit CLI executable, also supplied to the daemon. |
| `snapraid_manager_config_path` | `/etc/snapraid.conf` | CLI configuration path; parent directory must exist. |
| `snapraid_manager_cache_directory` | `/var/cache/snapraid-manager` | Verified package cache. |
| `snapraid_manager_data_disks` | `[]` | Required list of `{name, path}` data directories. |
| `snapraid_manager_parity_disks` | `[]` | Required list of `{level, path}` parity files. |
| `snapraid_manager_content_files` | `[]` | Required list of absolute content-file paths. |
| `snapraid_manager_excludes` | `[]` | SnapRAID exclude patterns. |
| `snapraid_manager_exclude_hidden` | `false` | Emit `nohidden`. |

## Optional daemon

```yaml
snapraid_manager_daemon_enabled: true
snapraid_manager_daemon_options:
  maintenance_schedule: "01:00"
  sync_threshold_deletes: 50
  sync_threshold_updates: 100
  scrub_percentage: 12
  scrub_older_than: 10
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `snapraid_manager_daemon_enabled` | `false` | Opt into daemon installation and service management. |
| `snapraid_manager_daemon_version` | `"2.1"` | Pinned daemon version. |
| `snapraid_manager_daemon_package_url` | Upstream release asset | Optional package mirror. |
| `snapraid_manager_daemon_package_checksum` | Pinned SHA-256 | Integrity check; update together with version. |
| `snapraid_manager_daemon_options` | `{}` | Overrides merged into the defaults in [vars/main.yml](vars/main.yml). |
| `snapraid_manager_required_mounts` | Data directories and parity parent directories | Exact mountpoints checked at deployment and before array access. Override when data lives below a mount root. |
| `snapraid_manager_daemon_hook` | `""` | Optional existing executable called after the mount guard with the daemon event argument. |
| `snapraid_manager_allow_daemon_restart` | `false` | Explicitly permit stopping an active daemon when configuration or packages change, or integration is disabled. |

Defaults enable the UI/API only on `127.0.0.1:7627`, retain logs for 120 days, disable spindown and automatic update checks and leave maintenance scheduling empty. 

Enabling the daemon alone does not schedule a sync. A schedule is a separate, explicit opt-in.

## Optional Healthchecks.io integration

The integration is disabled by default and requires daemon integration. Enable it with the complete HTTPS ping URL from your Healthchecks.io check, preferably stored in Ansible Vault:

```yaml
snapraid_manager_daemon_enabled: true
snapraid_manager_healthchecks_enabled: true
snapraid_manager_healthchecks_ping_url: "{{ vault_snapraid_healthchecks_ping_url }}"
```

| Variable | Default | Purpose |
| --- | --- | --- |
| `snapraid_manager_healthchecks_enabled` | `false` | Send maintenance-start, success, and failure pings. |
| `snapraid_manager_healthchecks_ping_url` | `""` | Secret HTTPS success endpoint, without a query, fragment, or embedded username/password. Self-hosted HTTPS endpoints are supported. |
| `snapraid_manager_healthchecks_timeout` | `10` | Connection and per-attempt timeout in seconds, from 1 to 60. |
| `snapraid_manager_healthchecks_retries` | `3` | Transient-error retries, from 0 to 5, with a 60-second retry budget. |

At the start of a maintenance task, the role sends Healthchecks' `/start` ping;
after successful maintenance the daemon sends the regular success ping, and a
maintenance report at `error` or `critical` sends `/fail`. 

The start and failure pings are filtered to maintenance, so heal, undelete, refresh, SMART, and unrelated reports do not signal this check.

The success, `/start`, and `/fail` URLs are stored in separate files under
`/etc/snapraid-manager` (`root:root`, `0600`) inside a `0700` directory. One shared root-owned helper dispatches start and failure events to their endpoint configs.

Only config-file paths appear in daemon commands. Template output/diffs and curl
diagnostics are suppressed; curl responses are discarded. The integration owns
`notify_heartbeat`, `notify_start`, `notify_result`, and `notify_result_level`, so do not set those options in `snapraid_manager_daemon_options`.
`notify_run_as_user` must be empty or `root` so curl can read the credentials.

Other notification providers remain independent.

## Notes

- Disk names are explicit and stable when lists are reordered. 
- Parity paths are full filenames and levels must be unique and contiguous from 1 to 6.
- Keep sufficient content-file copies on separate physical disks for your parity level; this role cannot infer physical failure domains from paths.
- Version overrides require matching URLs/checksums.
- Automatic downgrades are not supported.
- Configuration is fully Ansible-owned, including `/etc/snapraidd.conf` (`root:root`,`0600`). 
- Use `0`/`1`, not YAML booleans for numeric daemon switches.

## Releases

Push a stable semantic-version tag such as `v1.0.0` to create a GitHub Release.
The release job runs only after lint/unit tests and every platform integration
job pass, and generates release notes from merged pull requests.

## License

MIT for this role. SnapRAID and SnapRAID Daemon retain their own upstream licenses.