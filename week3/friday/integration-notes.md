# Integration Challenge Resolutions

---

## Challenge A: ProtectSystem=strict and the EnvironmentFile

### The Conflict

`ProtectSystem=strict` makes the entire filesystem read-only for the service process. The `EnvironmentFile` directive must read configuration at service startup. If the config file is under a path that `ProtectSystem=strict` makes read-only, the service fails to load its environment.

### Options Considered

1. **Place config files under /etc/kijanikiosk/** — Standard FHS location, but `/etc` is read-only under `ProtectSystem=strict`. Would require `ReadOnlyPaths=/etc/kijanikiosk` to explicitly re-allow reads, which is redundant because `/etc` is already read-only (not inaccessible). However, creating new directories under `/etc` during provisioning works fine since the unit file isn't active yet. The issue is that the service cannot _write_ to `/etc`, which is the intended behavior — config should be read-only.

2. **Place config files under /opt/kijanikiosk/config/** — This path is under `/opt`, which `ProtectSystem=strict` also makes read-only. But we add `ReadOnlyPaths=/opt/kijanikiosk/config` explicitly. Since the service only needs to _read_ the config (not write), read-only access is exactly correct.

3. **Use `BindReadOnlyPaths=`** — More explicit but functionally identical to `ReadOnlyPaths=` for this use case.

### Decision

Config files live at `/opt/kijanikiosk/config/{kk-api,kk-payments,kk-logs}.env` with ownership `root:kijanikiosk` and mode `640`. All three unit files declare `ReadOnlyPaths=/opt/kijanikiosk/config`. The provisioning script creates the env files in Phase 3 (before units are written in Phase 4), so they exist when `systemctl daemon-reload` processes the unit files.

### Why This Works

`ProtectSystem=strict` makes paths read-only, not inaccessible. `EnvironmentFile=` only needs read access. `ReadOnlyPaths=/opt/kijanikiosk/config` explicitly confirms this intent. Verification: `sudo -u kk-payments cat /opt/kijanikiosk/config/kk-payments.env` returns the file contents without error.

---

## Challenge B: The Monitoring User and ACL Defaults

### The Conflict

Phase 8 writes a health check JSON file to `/opt/kijanikiosk/health/`. The provisioning script runs as root, so the file would default to `root:root` ownership. But the monitoring system and Amina need to read this file without sudo. The health directory was not in Tuesday's access model.

### Options Considered

1. **Add ACLs on /opt/kijanikiosk/health/** — Similar to the shared logs directory, use `setfacl` to grant read access to specific users. Overkill for a simple read-only directory.

2. **Use kk-logs:kijanikiosk ownership with 750/640** — The kk-logs service is the natural writer for monitoring data. The kijanikiosk group includes all service accounts and amina, giving them read access through standard group permissions.

3. **Use root:kijanikiosk** — Root writes during provisioning, group reads. But this prevents kk-logs from writing health updates at runtime without sudo.

### Decision

Directory: `kk-logs:kijanikiosk 750`. File: `kk-logs:kijanikiosk 640`. The provisioning script creates the file as root and immediately `chown`s it. No ACLs needed — this is a single-writer, multiple-reader scenario where standard UGO permissions suffice. The `kijanikiosk` group membership handles all authorized readers.

### Why This Works

Every authorized reader (kk-api, kk-payments, kk-logs, amina) is a member of the `kijanikiosk` group. Group read permission (640) grants access. No sudo required. No ACL complexity. The health directory was added to `access-model-final.md`.

---

## Challenge C: logrotate postrotate and PrivateTmp

### The Conflict

The logrotate `postrotate` script needs to signal kk-logs to re-open log file handles after rotation. The standard approach is `systemctl reload kk-logs.service`. But:

- Does kk-logs have an `ExecReload=` directive? If not, `systemctl reload` fails.
- kk-logs has `PrivateTmp=true`. Does this interfere with the reload signal?

### Options Considered

1. **Use `systemctl reload kk-logs.service`** — Requires `ExecReload=` in the unit file. We added `ExecReload=/bin/kill -HUP $MAINPID` to the kk-logs unit. The reload signal is sent by systemd (PID 1), not by the logrotate process, so `PrivateTmp=true` on the service is irrelevant to signal delivery.

2. **Use `systemctl kill -s HUP kk-logs.service`** — Sends SIGHUP without requiring `ExecReload=`. Works but bypasses systemd's reload lifecycle (no state transition to "reloading").

3. **Use `systemctl restart kk-logs.service`** — Heavy-handed. Drops in-flight data during the restart window. Unnecessary when a HUP signal suffices.

### Decision

Added `ExecReload=/bin/kill -HUP $MAINPID` to the kk-logs unit file. The postrotate script uses `systemctl reload kk-logs.service 2>/dev/null || true`. The `|| true` ensures logrotate does not fail if kk-logs is not running (e.g., during provisioning when no app code is deployed).

### Why PrivateTmp Is Not a Problem

`PrivateTmp=true` isolates the `/tmp` and `/var/tmp` mount namespaces for the service process. It has no effect on signal delivery. `systemctl reload` instructs systemd (PID 1) to send SIGHUP to the service's main PID. This is a kernel-level signal operation, not a filesystem operation. The private tmp namespace is irrelevant.

For kk-api and kk-payments: these services write to the journal (`StandardOutput=journal`), not directly to the rotated log files. They do not need a postrotate signal. The `sharedscripts` directive ensures the postrotate runs once for all rotated files, targeting only kk-logs.

---

## Challenge D: The Dirty VM and Package Holds

### The Conflict

The VM has been used for four days of labs. Packages may be installed, partially configured, or at unexpected versions. `apt-mark hold` may or may not already be set. Running `apt-get install nginx=1.24.0-2ubuntu7.6` on a VM where nginx is already at that version succeeds idempotently. But if nginx was accidentally upgraded, the install attempts a downgrade, which may conflict with existing holds.

### Options Considered

1. **Check versions first, skip if matching** — Safest approach. Compare installed versions against pinned versions. If they match, skip the install entirely. If they differ, unhold → install → re-hold.

2. **Always unhold → install → hold** — Simpler. `apt-mark unhold` is idempotent (no error if not held). Then install at the pinned version. Then hold again. Works whether the package was held, not held, at the right version, or at a different version.

3. **Fail loudly if versions don't match** — Abort the script if the installed version differs from the pinned version. Safest but requires manual intervention.

### Decision

Option 2: Always `apt-mark unhold` both packages before install, then install at pinned versions, then `apt-mark hold`. This handles all dirty states:

- Package not installed → install + hold
- Package at correct version and held → unhold + reinstall (no-op) + hold
- Package at wrong version and held → unhold + install correct version + hold
- Package at correct version but not held → reinstall (no-op) + hold

The script also logs the currently installed versions before attempting any install, providing an audit trail of what state was found. This approach is both idempotent and self-documenting.

### Why Not Fail Loudly

In a production environment, failing loudly is often the right choice — you want a human to investigate unexpected version drift. But this is a staging VM used for labs. The "dirty state" is expected, not anomalous. The script's purpose is specifically to bring a dirty VM to a known state. Failing on expected dirt would defeat the purpose.
