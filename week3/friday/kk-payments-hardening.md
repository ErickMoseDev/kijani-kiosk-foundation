# kk-payments.service — Iterative Hardening Log

Target: systemd-analyze security score **below 2.5**

---

## Starting Point: Baseline Score

Unit file with only `User=kk-payments`, `Group=kk-payments`, and basic service directives (Type, WorkingDirectory, ExecStart, Restart). No hardening directives.

```
→ Overall exposure level for kk-payments.service: 9.2 UNSAFE
```

---

## Iteration 1: Core Filesystem and Privilege Isolation

Added:

```ini
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
ReadWritePaths=/opt/kijanikiosk/shared/logs
ReadOnlyPaths=/opt/kijanikiosk/config
```

**Rationale:** These are baseline hardening directives covered in Wednesday's lab. `ProtectSystem=strict` makes the entire filesystem read-only except for explicitly allowed paths. `PrivateTmp=true` gives the service its own /tmp namespace.

```
→ Score after: 7.8 EXPOSED
```

Change: 9.2 → 7.8 (−1.4)

---

## Iteration 2: Drop All Capabilities

Added:

```ini
CapabilityBoundingSet=
AmbientCapabilities=
```

**Rationale:** Empty `CapabilityBoundingSet=` removes all Linux capabilities from the bounding set. The payments service is a Node.js application that binds to port 3001 (>1024) and needs zero elevated privileges. This single directive flips ~30 capability checks.

```
→ Score after: 4.6 MEDIUM
```

Change: 7.8 → 4.6 (−3.2)

---

## Iteration 3: Kernel Protection Suite

Added:

```ini
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
```

**Rationale:** Blocks the service from modifying kernel parameters, loading modules, reading kernel log buffer, modifying cgroups, adjusting the system clock, or changing the hostname. None of these are needed by a payments API.

```
→ Score after: 3.6 MEDIUM
```

Change: 4.6 → 3.6 (−1.0)

---

## Iteration 4: Restrict Namespaces, Realtime, SUID

Added:

```ini
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
LockPersonality=true
MemoryDenyWriteExecute=true
RemoveIPC=true
```

**Rationale:** `RestrictNamespaces=true` prevents the use of Linux namespaces (blocks container escape techniques). `MemoryDenyWriteExecute=true` blocks W^X violations — prevents an attacker from writing shellcode to memory and then executing it. `RestrictSUIDSGID=true` prevents creating SUID/SGID binaries.

```
→ Score after: 2.9 MEDIUM
```

Change: 3.6 → 2.9 (−0.7)

---

## Iteration 5: System Call Filtering and Network Restrictions

Added:

```ini
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources @mount @clock @debug @obsolete @raw-io @reboot @swap @cpu-emulation @module
UMask=0077
```

**Rationale:** `SystemCallArchitectures=native` blocks execution of non-native binaries (prevents x86 on x64 attacks). The allowlist-then-denylist approach starts with the `@system-service` group (normal service operations) and then explicitly removes dangerous groups. `UMask=0077` ensures any files created by the service are only accessible to the owner.

```
→ Score after: 2.3 OK
```

Change: 2.9 → 2.3 (−0.6)

---

## Iteration 6: Process Visibility and Network Address Restriction

Added:

```ini
ProtectProc=invisible
ProcSubset=pid
PrivateUsers=true
PrivateDevices=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
IPAddressAllow=localhost
IPAddressDeny=any
InaccessiblePaths=/opt/kijanikiosk/api
TemporaryFileSystem=/var:ro
```

**Rationale:** `ProtectProc=invisible` hides other processes from the payments service (it can only see its own PID namespace). `IPAddressAllow=localhost` combined with `IPAddressDeny=any` ensures the service only accepts connections from the loopback interface. `InaccessiblePaths=/opt/kijanikiosk/api` prevents the payments service from reading the API service's code. `RestrictAddressFamilies` limits socket types.

```
→ Score after: 2.1 OK
```

Change: 2.3 → 2.1 (−0.2)

---

## Directives Investigated but NOT Applied

### 1. `PrivateNetwork=true`

**What it does:** Creates a completely isolated network namespace with only a loopback interface. No external network access at all.

**Why rejected:** The payments service must accept incoming TCP connections on port 3001 from the nginx reverse proxy. `PrivateNetwork=true` would make the service completely unreachable, even from localhost when accessed via the host's network stack. While `IPAddressAllow=localhost` achieves network restriction at a higher level, `PrivateNetwork=true` is too aggressive — it breaks the fundamental connectivity requirement. Score improvement would be ~0.1, but the service would fail health checks and be non-functional.

### 2. `DynamicUser=true`

**What it does:** Creates a transient user for the service at runtime, allocating a UID from a reserved range and removing it when the service stops. Files are managed through `StateDirectory=`, `LogsDirectory=`, etc.

**Why rejected:** Our access model relies on the `kk-payments` user existing persistently so that ACLs on `/opt/kijanikiosk/shared/logs/` (set via `setfacl -m u:kk-payments:rwx`) continue to work. `DynamicUser=true` would assign a different UID each restart, breaking all ACL entries. The entire shared logging model from Tuesday depends on persistent UIDs. Re-architecturing the ACL model for this ~0.1 score improvement is not worth the integration risk.

---

## Final Score

```
→ Overall exposure level for kk-payments.service: 2.1 OK ✓
```

**Target: < 2.5** — ACHIEVED

---

## Final Unit File

```ini
[Unit]
Description=KijaniKiosk Payments Service
Documentation=https://github.com/kijanikiosk/payments
After=network.target kk-api.service
Wants=network.target kk-api.service
StartLimitIntervalSec=300
StartLimitBurst=5

[Service]
Type=simple
User=kk-payments
Group=kk-payments
WorkingDirectory=/opt/kijanikiosk/payments
EnvironmentFile=/opt/kijanikiosk/config/kk-payments.env
ExecStart=/usr/bin/node /opt/kijanikiosk/payments/server.js
Restart=on-failure
RestartSec=5

# Security hardening (target: < 2.5)
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
PrivateDevices=true
PrivateUsers=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectKernelLogs=true
ProtectControlGroups=true
ProtectClock=true
ProtectHostname=true
ProtectProc=invisible
ProcSubset=pid
RestrictNamespaces=true
RestrictRealtime=true
RestrictSUIDSGID=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
LockPersonality=true
MemoryDenyWriteExecute=true
RemoveIPC=true
CapabilityBoundingSet=
AmbientCapabilities=
SystemCallArchitectures=native
SystemCallFilter=@system-service
SystemCallFilter=~@privileged @resources @mount @clock @debug @obsolete @raw-io @reboot @swap @cpu-emulation @module
UMask=0077
IPAddressAllow=localhost
IPAddressDeny=any

# Filesystem access
ReadWritePaths=/opt/kijanikiosk/shared/logs
ReadOnlyPaths=/opt/kijanikiosk/config
InaccessiblePaths=/opt/kijanikiosk/api
TemporaryFileSystem=/var:ro

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=kk-payments

[Install]
WantedBy=multi-user.target
```
