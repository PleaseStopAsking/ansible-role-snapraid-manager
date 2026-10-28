# Migrating from the archived SnapRAID role

This guide is explicit and opt-in. The new role does not edit old cron entries,
remove snapraid-runner, change enterprise requirements, or migrate any host by itself.

## Review findings from the local projects

- The old role installs runner configuration (including SMTP/Pushover credentials)
  with mode `0775`. The new daemon configuration is `0600`; assess old credential
  exposure and rotate secrets where appropriate.
- Switching the old `snapraid_runner` flag does not remove jobs from the other
  scheduling mode. Check for both runner and direct sync/scrub cron entries.
- Data disk names and parity levels are generated from list position. The new
  role requires explicit names/levels to avoid unintended identity changes.
- The old CLI template writes `/etc/snapraid.conf` even when its configuration
  path variable is changed. The new role uses one explicit path consistently.
- The old installer builds from an unpinned external repository, and runner Git
  checkout is also unpinned. The new role verifies version-pinned release assets.
- Old metadata/release automation references the upstream author and platforms
  the tasks do not actually install on. New metadata and CI belong to the new role.

## Procedure

1. Back up the current CLI configuration, content files, runner configuration,
   crontab, and recorded CLI version. Keep disk names, paths, and parity levels.
   Review SnapRAID upgrade notes before replacing an older CLI. This role does
   not back up large parity files or provide automatic rollback of array formats.
2. Stop scheduling new work and wait for any active runner or CLI operation to
   finish. Remove only the legacy jobs you own. Their default Ansible cron names
   are `snapraid_runner`, `snapraid sync`, and `snapraid scrub`. Cron labels are
   configurable, so inspect `crontab -l` as root. Also inspect any custom timers.
3. Record existing disk names from the deployed config rather than assuming they
   match current inventory order. Translate to the explicit schema below.
4. Apply the new role with daemon integration disabled. Compare the rendered CLI
   configuration against the backup. Do not initialize parity or change array
   identities as part of this deployment.
5. Enable daemon integration with `maintenance_schedule: ""`. Confirm discovery,
   disk mappings, UI access restrictions, required mounts, and notification tools.
6. Configure a maintenance schedule only after reviewing safety thresholds and
   confirming no competing scheduler remains. If the daemon is running, explicitly
   allow a restart in a verified idle maintenance window.
7. Observe the first scheduled maintenance and confirm successful reporting and
   Healthchecks. Retain the old runner files until the migration is accepted.

## Geordi configuration mapping

The following preserves the identities and paths in the current enterprise playbook:

```yaml
snapraid_manager_data_disks:
  - name: d1
    path: /mnt/data1
  - name: d2
    path: /mnt/data2
snapraid_manager_parity_disks:
  - level: 1
    path: /mnt/parity1/snapraid.parity
  - level: 2
    path: /mnt/parity2/snapraid.parity
snapraid_manager_content_files:
  - /var/snapraid.content
  - /mnt/data1/.snapraid.content
  - /mnt/data2/.snapraid.content
snapraid_manager_excludes:
  - '*.unrecoverable'
  - /lost+found/
  - '*.!sync'
  - /tmp/
  - downloads/
  - downloads-complete/
  - appdata/
  - aquota.user
  - aquota.group
  - .content
  - '*.bak'
  - '/snapraid.conf*'
snapraid_manager_daemon_enabled: true
snapraid_manager_daemon_options:
  maintenance_schedule: ""
  sync_threshold_deletes: 251
  sync_threshold_updates: 0
  scrub_percentage: 22
  scrub_older_than: 8
  touch_zero_subseconds: 1
```

The old runner aborts when deletions are **greater than 250**. The daemon aborts
when deletions are **greater than or equal to** its configured value, so `251`
preserves that exact boundary. Setting `250` is a valid, slightly stricter choice.
The old runner has no update threshold; `sync_threshold_updates: 0` preserves
that behavior. Consider introducing an update threshold intentionally instead of
carrying this compatibility choice into a new deployment.

After the unscheduled validation phase, use `maintenance_schedule: "01:00"` to
match the old nightly cron time. Review timezone/DST behavior for the selected
daemon release rather than assuming every cron behavior carries over.

The daemon heartbeat is a successful-maintenance ping, not a complete replacement
for the old shell wrapper's start/success sequence. Configure `notify_start`
separately if start pings are needed, accounting for its additional event types.
Pushover credentials cannot simply be copied into old variable names: provision a
notification helper and reference it via `notify_result`, or choose another provider.

To roll back scheduling, stop/disable the daemon and confirm no CLI task remains
before restoring legacy cron. Preserve content and parity. Downgrading the CLI
after a newer release has written array metadata needs separate compatibility
review; restoring an old executable alone is not a safe general rollback plan.
