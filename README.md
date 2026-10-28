# ansible-role-snapraid-manager

Manage SnapRAID and, optionally, [SnapRAID Daemon](https://github.com/amadvance/snapraid-daemon)
on Debian and Ubuntu amd64 hosts. Galaxy role name: `snapraid_manager`.

This is a new, standalone implementation, not a continuation of the archived
IronicBadger role. It does not depend on snapraid-runner. The daemon owns scheduling;
the role creates no cron jobs or systemd timers.

## Support and requirements

- Initial target matrix: Debian 12/13 and Ubuntu 24.04, amd64. Support remains provisional until native integration CI passes.
- Controller: ansible-core 2.19 or newer; Python and `python3-apt` on targets.
- Root privileges (`become: true`) and gathered facts.
- Systemd is required only when daemon integration is enabled.
- Existing storage mounts and directories. The role never formats, mounts, or creates storage disks.
- Initial pins: SnapRAID 15.1 and SnapRAID Daemon 2.1, installed from upstream `.deb` assets with SHA-256 verification.

No Galaxy publication exists yet. The namespace in metadata is provisional until
verified against the publisher's Galaxy account. For local testing, keep the
directory named `ansible-role-snapraid-manager` and add its parent to `roles_path`.
Once published, use the actual Galaxy namespace and a tagged role release.

## Minimal example

```yaml
- name: Configure parity array
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

Disk names are explicit and stable when lists are reordered. Parity paths are full
filenames and levels must be unique and contiguous from 1 to 6. Keep sufficient
content-file copies on separate physical disks for your parity level; this role
cannot infer physical failure domains from paths.

## Core variables

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

Version overrides require matching URLs/checksums. Automatic downgrades are not
supported. With `install: false`, the executable must already exist; daemon package
dependencies still require a compatible dpkg-installed `snapraid` package.

## Optional daemon

```yaml
snapraid_manager_daemon_enabled: true
snapraid_manager_daemon_options:
  maintenance_schedule: "01:00"
  sync_threshold_deletes: 50
  sync_threshold_updates: 100
  scrub_percentage: 12
  scrub_older_than: 10
  notify_heartbeat: "curl -fsS --max-time 30 --retry 3 https://hc-ping.com/YOUR_UUID"
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

Defaults enable the UI/API only on `127.0.0.1:7627`, retain logs for 120 days,
disable spindown and automatic update checks, and leave maintenance scheduling
empty. Enabling the daemon alone does not schedule a sync. A schedule is a separate,
explicit opt-in. The daemon performs discovery/telemetry at startup, so it is not
a passive process. SnapRAID 15.1 or newer is required for daemon integration.

Configuration is fully Ansible-owned, including `/etc/snapraidd.conf` (root:root,
`0600`). UI/API changes are temporary: the next successful role application restores
inventory settings. Unknown settings are rejected. Use `0`/`1`, not YAML booleans,
for numeric daemon switches. `sys_engine` and `hook_script` are managed through the
dedicated role variables and cannot be overridden through the options dictionary.
Repeated `sys_smartignore` directives are not supported in this initial version.

The daemon's package scripts call systemctl directly. The role masks the service
during package installation and unmasks it only after configuration is installed.
If installation fails, the service may remain stopped/masked; fix the error and
rerun the role. Configuration changes require a restart because `sys_*` settings
cannot be reloaded in daemon 2.1. Idempotent runs do not stop the daemon.

Before permitting a restart, wait until the daemon queue is empty and suspend
scheduled work. Stopping the daemon can terminate an active CLI operation; this
role does not promise a race-free automatic idle window. It does not start sync,
scrub, recovery, or parity initialization itself. A configured daemon schedule
can of course run once the service is enabled.

Disabling integration stops/disables a service previously adopted by this role,
subject to the same restart permission. Packages, configuration, logs, and support
files are retained. An unrelated daemon installation is not disabled just because
the default integration switch is off.

## Network and notifications

Remote access must be explicitly configured using `net_port`, `net_acl`, and
`net_auth_credential` in `daemon_options`. Supply an upstream-format Argon2id
credential hash through Ansible Vault; do not put plaintext passwords in inventory.
Use HTTPS at a reverse proxy or an encrypted VPN. Basic authentication without
transport encryption is not sufficient. The upstream `/metrics` endpoint is
exempt from authentication, so network restrictions still matter.

Keep `net_config_full_access: 0` unless you deliberately want remote modification
of sensitive command/hook settings. This flag does not make the entire UI read-only.

Healthchecks uses `notify_heartbeat`. Other notification providers use
`notify_result`, optionally `notify_start`, and existing commands or scripts.
Pushover is not a built-in integration in this role. For SMTP, prefer a dedicated
credentials file and curl's `--netrc-file`; this role does not overwrite `/root/.netrc`.
Provision notification tools/scripts separately and ensure the notification user
can read required credentials. Treat all hook and notification commands as trusted
code. The role suppresses daemon config diffs/task output but cannot prevent
secrets in user-supplied commands from appearing in process arguments or daemon logs.

## Testing

```sh
ansible-galaxy collection install -r tests/requirements.yml -p .ansible/collections
ansible-lint --offline
ansible-playbook -i localhost, tests/core.yml
bash tests/integration.sh debian:13
```

Core tests only validate and render configuration; they do not manage the local
machine. Integration tests require Docker and build disposable privileged **amd64**
containers with systemd and tmpfs test disks. They never attach host storage disks.
Full integration requires a native amd64 Docker host. The amd64 daemon's child
execution and forking service startup did not work reliably under this development
machine's ARM Docker emulation; direct CLI execution and core convergence did work.
Use `bash tests/integration.sh debian:13 core` for CLI-only convergence/idempotence
under emulation. Core-only mode is not a substitute for the full native CI gate.
Tests cover package installation, daemon startup, core/daemon idempotence, runtime
mount checks, configuration ownership, restart protection, and disabling integration.
CI targets Debian 12/13 and Ubuntu 24.04. Real-disk SMART/spindown behavior and a
production-array migration require separate operator validation.

Do not change daemon configuration through the UI/API while an Ansible deployment
is running; concurrent writers can race with configuration inspection and replacement.

### Current validation status

- Ansible lint: production profile, no failures or warnings.
- Host-safe validation/rendering suite: 65 successful tasks, including five expected rejection cases.
- CLI package installation and zero-change second runs: passed on Debian 12, Debian 13, and Ubuntu 24.04 amd64 containers.
- Both pinned package checksums: verified against downloaded release assets.
- Full daemon lifecycle suite: not passed locally; requires native amd64 CI before publication.
- Live-array migration, physical SMART telemetry, spindown, and external notifications: not exercised.

Check mode predicts configuration/package changes but does not install downloaded
packages or start the daemon. A fresh-host check is not a substitute for convergence.

## Migration and publication

See [MIGRATION.md](MIGRATION.md) for the archived-role migration, including an
example matching Geordi's existing array. Do not run both schedulers together.

Before publication, confirm the Galaxy namespace and MIT license choice, run all
CI gates, review the supported-distribution matrix, and create a semantic-version
tag (start at `v1.0.0` only after release validation). Configure Galaxy import for
the new GitHub repository; no old-fork import workflow or tokens are reused here.
Development repository: [PleaseStopAsking/ansible-role-snapraid-manager](https://github.com/PleaseStopAsking/ansible-role-snapraid-manager).
The repository is private during validation. No Galaxy release or public
publication is performed automatically; repository visibility changes require
explicit approval.

References: [daemon manual](https://www.snapraid.it/manual-daemon),
[daemon 2.1 configuration](https://github.com/amadvance/snapraid-daemon/blob/v2.1/snapraidd.conf.example),
[SnapRAID manual](https://www.snapraid.it/manual). Tagged release behavior takes
precedence where the live manual differs.

## License

MIT for this role. SnapRAID and SnapRAID Daemon retain their own upstream licenses.
