# KijaniKiosk API Service — systemd Security Analysis

## Score Summary

| State                                  | Score   | Rating     |
| -------------------------------------- | ------- | ---------- |
| Before hardening (no directives)       | 9.2     | UNSAFE     |
| After original hardening directives    | 8.3     | EXPOSED    |
| After adding two additional directives | **5.6** | **MEDIUM** |

## Before Hardening — 9.2 UNSAFE

With only `User=` and `Group=` set (no hardening directives), almost every check fails.
The service has full access to the filesystem, home directories, tmp, kernel tunables,
all Linux capabilities, and no system call filtering.

```
Selected failures (before):
✗ NoNewPrivileges=           Service processes may acquire new privileges               0.2
✗ ProtectSystem=             Service has full access to the OS file hierarchy           0.2
✗ ProtectHome=               Service has full access to home directories                0.2
✗ PrivateTmp=                Service has access to other software's temporary files     0.2
✗ CapabilityBoundingSet=~CAP_SYS_ADMIN  Service has administrator privileges           0.3
✗ ProtectKernelTunables=     Service may alter kernel tunables                          0.2
→ Overall exposure level for kk-api.service: 9.2 UNSAFE 😨
```

## After Original Hardening — 8.3 EXPOSED

Adding the five original directives improved the score:

```ini
ProtectSystem=strict
ReadWritePaths=/opt/kijanikiosk/shared/logs
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true
```

These flip five checks to a tick but leave all capabilities unrestricted and kernel tunables
unprotected. Score dropped from 9.2 to 8.3.

## After Two Additional Directives — 5.6 MEDIUM

```ini
CapabilityBoundingSet=
ProtectKernelTunables=true
```

Score dropped from 8.3 to **5.6** — a 3.6 point improvement. The bulk of this comes from
`CapabilityBoundingSet=` which flips ~30 capability checks from an x to a tick in one line.

```
Selected results (after):
✓ NoNewPrivileges=           Service processes cannot acquire new privileges
✓ ProtectSystem=             Service has strict read-only access to the OS file hierarchy
✓ ProtectHome=               Service has no access to home directories
✓ PrivateTmp=                Service has no access to other software's temporary files
✓ CapabilityBoundingSet=~CAP_SYS_ADMIN  Service has no administrator privileges
✓ ProtectKernelTunables=     Service cannot alter kernel tunables (/proc/sys, …)
✓ CapabilityBoundingSet=~CAP_SYS_MODULE Service cannot load kernel modules
✓ CapabilityBoundingSet=~CAP_NET_ADMIN  Service has no network configuration privileges
→ Overall exposure level for kk-api.service: 5.6 MEDIUM 😐
```

---

## Additional Directive 1: `CapabilityBoundingSet=`

### What it does at the kernel level

Setting `CapabilityBoundingSet=` (empty value) drops **all** Linux capabilities from the
bounding set of the service process. The kernel capability bounding set acts as an upper
limit on which capabilities a process can ever acquire, regardless of file capabilities or
setuid bits. An empty bounding set means the process cannot gain any capability—not through
`execve()` of a capability-bearing binary, not through any child process, not at all.

### Concrete attack it blocks

**Privilege escalation via `CAP_SYS_ADMIN`**: Without this directive, if an attacker gains
code execution inside the kk-api Node.js process, they could potentially mount filesystems (`mount()`),
manipulate namespaces, load eBPF programs, or call `ptrace()` to attach to other processes
, all of which are gated by capabilities that the process would otherwise be allowed to
acquire. With `CapabilityBoundingSet=`, this entire class of post-exploitation capability
escalation is blocked at the kernel level. The kernel refuses the capability grant before
the syscall even executes.

## Additional Directive 2: `ProtectKernelTunables=true`

### What it does at the kernel level

This directive mounts `/proc/sys`, `/sys`, `/proc/sysrq-trigger`, `/proc/latency_stats`,
`/proc/acpi`, and `/proc/timer_stats` as read-only inside the service's mount namespace.
The kernel enforces this at the VFS layer, any `write()` or `open(..., O_WRONLY)` syscall
targeting these paths returns `EROFS` (read-only filesystem).

### Concrete attack it blocks

**Disabling ASLR via `/proc/sys/kernel/randomize_va_space`**: An attacker who achieves
code execution inside the API service could write `0` to
`/proc/sys/kernel/randomize_va_space`, disabling Address Space Layout Randomization
system-wide. This makes every process on the server predictable in memory layout, enabling
reliable exploitation of buffer overflow vulnerabilities in any service (not just kk-api).
With `ProtectKernelTunables=true`, the write is rejected by the kernel's VFS layer before
it reaches the procfs handler, keeping ASLR intact for the entire system.
