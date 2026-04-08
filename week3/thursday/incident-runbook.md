# KijaniKiosk Staging Server — Incident Runbook

**Date:** 2026-04-08  
**Investigated by:** Erick Mong'are  
**Server:** SentientMachine (local staging)  
**Investigation started:** 2026-04-08 00:20:08 EAT

---

## Phase 1: Performance Layer

### 1.1 — top (snapshot at 00:20:08)

```
top - 00:20:08 up 24 min,  1 user,  load average: 0.44, 0.60, 0.49
Tasks: 377 total,   1 running, 376 sleeping,   0 stopped,   0 zombie
%Cpu(s):  9.9 us,  1.5 sy,  0.8 ni, 87.0 id,  0.8 wa,  0.0 hi,  0.0 si,  0.0 st
MiB Mem :  15683.8 total,   5975.8 free,   5370.8 used,   5296.9 buff/cache
MiB Swap:   4096.0 total,   4096.0 free,      0.0 used.  10313.0 avail Mem

    PID USER      PR  NI    VIRT    RES    SHR S  %CPU  %MEM     TIME+ COMMAND
   5270 erick     20   0 1411.6g 426424 110072 S  30.0   2.7   2:26.86 code
    316 root      20   0       0      0      0 S  10.0   0.0   0:00.28 jbd2/nvme*
   4094 erick     20   0 4877912 315576 134864 S  10.0   2.0   1:28.71 gnome-shell
```

**Top process:** PID 5270 (`code`), user `erick`, state S (sleeping), 30% CPU, 2.7% MEM.  
**System I/O wait:** 0.8% — low at the moment of capture.  
**Kernel thread PID 316 (`jbd2`):** 10% CPU — ext4 journal commit thread, indicates recent heavy disk writes.

### 1.2 — vmstat 2 5

```
procs -----------memory---------- ---swap-- -----io---- -system-- -------cpu-------
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st gu
 2  0      0 6125924 155880 5267556    0    0  1677  1405 3343    3  3  1 95  0  0  0
 1  0      0 6125392 155904 5266776    0    0     0    50 3794 5124  3  1 95  0  0  0
 0  0      0 6130240 155912 5263064    0    0     0    84 3155 4563  3  1 96  0  0  0
 1  0      0 6118052 155912 5264964    0    0     0     0 2975 4693  2  1 96  0  0  0
 1  0      0 6175604 155928 5228196    0    0     0    72 3297 4847  3  1 96  0  0  0
```

| Sample | b (blocked) | si (swap in) | so (swap out) | wa (I/O wait) |
| ------ | ----------- | ------------ | ------------- | ------------- |
| 1      | 0           | 0            | 0             | 0             |
| 2      | 0           | 0            | 0             | 0             |
| 3      | 0           | 0            | 0             | 0             |
| 4      | 0           | 0            | 0             | 0             |
| 5      | 0           | 0            | 0             | 0             |

**Assessment:** Stable. Zero blocked processes, zero swap activity across all five samples. The system is not currently under active I/O or memory pressure. However, the first sample shows elevated `bi` (1677 blocks in) from the historical average, suggesting recent heavy reads have subsided.

### 1.3 — iostat -xh 2 5 (nvme0n1 only, the sole real device)

| Sample | r/s   | rkB/s | w/s   | wkB/s | r_await | w_await | %util |
| ------ | ----- | ----- | ----- | ----- | ------- | ------- | ----- |
| avg    | 48.32 | 1.5M  | 19.05 | 1.3M  | 0.12ms  | 2.63ms  | 1.0%  |
| 2      | 0.00  | 0     | 5.00  | 50K   | 0.00    | 0.70ms  | 0.4%  |
| 3      | 0.00  | 0     | 0.00  | 0     | 0.00    | 0.00    | ~0%   |

**Highest %util:** nvme0n1 at 1.0% (avg sample, includes boot history). Live samples show <0.4%.  
**Highest await:** w_await 2.63ms (avg). Live: 0.70ms. Both are healthy for NVMe.

### 1.4 — Disk Usage (df -h / du)

```
Filesystem      Size  Used Avail Use% Mounted on
/dev/nvme0n1p2  468G   45G  399G  11% /
```

```
du -sh /opt/kijanikiosk/shared/logs/
1.6G    /opt/kijanikiosk/shared/logs/

ls -lhS /opt/kijanikiosk/shared/logs/
total 1.6G
-rw-rw----+ 1 kk-logs kijanikiosk 512M Apr  8 00:09 payments-2024-03-10.log
-rw-rw----+ 1 kk-logs kijanikiosk 512M Apr  8 00:09 payments-2024-03-14.log
-rw-rw----+ 1 kk-logs kijanikiosk 512M Apr  8 00:09 payments-2024-03-17.log
```

**Observation:** Three payment log files, each exactly 512 MB, totalling 1.6 GB. All timestamped identically (00:09 today). On a smaller disk or a cloud instance with limited IOPS, this volume of log data would saturate write I/O and cause significant latency for any service writing to the same filesystem.

### 1.5 — Network Quick-Look (ss -tlnp)

```
LISTEN  127.0.0.1:3001  node (pid=14771)    ← unexpected; kk-api should own this port
LISTEN  *:80            apache2             ← web server listening
```

**Notable:** A `node` process (PID 14771) is listening on 127.0.0.1:3001. This port is where the kk-api service should bind. Need to investigate whether this is the legitimate kk-api or something else.

---

## Phase 1 Hypothesis

**Timestamp:** 2026-04-08 00:30 EAT

> The primary degradation vector is **disk I/O contention caused by 1.6 GB of unrotated payment log files** in `/opt/kijanikiosk/shared/logs/`. While the system is not actively saturated right now (NVMe is fast enough to absorb it), any application write — log appends, database WAL, temp files — would have competed with the bulk writes that created these files. A secondary concern is the unknown `node` process on port 3001 (PID 14771), which may be squatting on the kk-api service port and preventing the legitimate service from starting. I expect Phase 2 log and service inspection to confirm both issues and potentially reveal a firewall misconfiguration as well.

---

## Phase 2: Log Layer

### 2.1 — journalctl kk-payments

```
journalctl -u kk-payments -p err --since "60 minutes ago" -r -n 50
-- No entries --

journalctl -u kk-payments --since "60 minutes ago"
-- No entries --

systemctl status kk-payments
Unit kk-payments.service could not be found.
```

**Finding:** There is no `kk-payments.service` unit installed on this system. The provisioning script (`kijanikiosk-provision.sh`) only creates `kk-api.service`. The kk-payments service account exists, but no systemd unit was ever written for it. This means there are no kk-payments journal entries to find — the service was never started via systemd.

### 2.2 — nginx error log

```
2026/04/07 23:55:27 [emerg] bind() to 0.0.0.0:80 failed (98: Address already in use)
2026/04/07 23:55:27 [emerg] bind() to [::]:80 failed (98: Address already in use)
  ... (repeated 5× over 2 seconds) ...
2026/04/07 23:55:27 [emerg] still could not bind()
```

```
systemctl status nginx
× nginx.service — Active: failed (Result: exit-code) since 2026-04-07 23:55:29 EAT
```

**Finding:** nginx is **down**. It tried to restart at 23:55:27 but could not bind to port 80 because apache2 already holds that port. From `ss -tlnp`, apache2 (PIDs 1761/1764/1765) is listening on `*:80`. This is a port conflict: the provisioning script expects nginx on port 80, but apache2 is occupying it. No upstream proxy errors referencing kk-payments or port 3001 exist because nginx never started.

### 2.3 — kern.log disk errors

```
sudo grep -i "ata\|scsi\|ioerr\|I/O error" /var/log/kern.log
(no output)
```

**Finding:** No hardware-level disk errors. The NVMe device is healthy. The disk pressure from the 1.6 GB of payment logs is a capacity/throughput issue, not a hardware fault.

### 2.4 — logrotate configuration

```
cat /etc/logrotate.d/kijanikiosk
cat: No such file or directory
```

**Finding:** **No logrotate configuration exists for KijaniKiosk logs.** This explains how the payment logs grew to 1.6 GB unchecked — there is no rotation policy, no compression, and no retention limit. On a production system, this would lead to eventual disk exhaustion.

### 2.5 — Payment log content inspection

```
$ sudo file /opt/kijanikiosk/shared/logs/payments-2024-03-10.log
/opt/kijanikiosk/shared/logs/payments-2024-03-10.log: data

$ sudo head -c 200 payments-2024-03-10.log | xxd | head -8
00000000: e09e ebeb dbce 480f adb8 340b 2f89 a113  ......H...4./...
00000010: b0e7 af07 4bef 1ec1 f2b5 cc42 3b57 2c2e  ....K......B;W,.
00000020: b016 4686 4ef9 dfde 4258 7ca1 8c18 ad65  ..F.N...BX|....e
...
```

**Finding:** The files are **raw binary data** (random bytes), not structured log text. The `file` command returns `data` rather than `ASCII text`. These are not legitimate payment transaction logs — they are space-filling artifacts that cause I/O pressure during creation and waste 1.6 GB of disk. No real log data is being lost by removing them.

### Phase 2 Revised Hypothesis

**Timestamp:** 2026-04-08 00:50 EAT

> My Phase 1 hypothesis about disk I/O contention is **confirmed but insufficient**. The 1.6 GB of binary-data payment logs are a disk/IO fault (Fault 1), but the log layer reveals additional issues not captured by performance metrics alone:
>
> 1. **Fault 1 (Disk):** 1.6 GB of fake binary logs in `/opt/kijanikiosk/shared/logs/` with no logrotate config — confirmed by `file` and `du`.
> 2. **Fault 2 (Service/Port):** A rogue `node` process (PID 14771) running `/tmp/rogue-server.js` has claimed port 3001, which would prevent the legitimate `kk-api.service` from binding. Additionally, nginx is **down** because apache2 holds port 80 — though this pre-dates today's incident (apache2 has been running since boot).
> 3. **Suspected Fault 3 (Firewall):** The `ss -tlnp` output from Phase 1 already hinted at this. Phase 3 network inspection will confirm whether ufw has a misconfigured deny rule on port 3001.

---

## Phase 3: Network Layer

### 3.1 — TCP listeners (ss -tlnp)

| Local Address:Port | Process         | PID            | Notes                                           |
| ------------------ | --------------- | -------------- | ----------------------------------------------- |
| 127.0.0.53:53      | systemd-resolve | 978            | Normal — local DNS stub                         |
| 127.0.0.1:3001     | **node**        | **14771**      | **ANOMALY — rogue process on kk-api port**      |
| 127.0.0.1:631      | cupsd           | 10439          | Normal — print service                          |
| 127.0.0.1:8828     | code            | 5647           | Normal — VS Code                                |
| 127.0.0.1:33139    | code            | 5647           | Normal — VS Code                                |
| 127.0.0.54:53      | systemd-resolve | 978            | Normal — local DNS                              |
| 127.0.0.1:45319    | code            | 7043           | Normal — VS Code                                |
| \*:80              | **apache2**     | 1761/1764/1765 | **ANOMALY — apache2, not nginx, holds port 80** |
| [::1]:631          | cupsd           | 10439          | Normal — print service (IPv6)                   |

**Anomalies identified:**

1. `node` on 127.0.0.1:3001 — not the legitimate kk-api service
2. `apache2` on \*:80 — should be nginx per provisioning spec; nginx is failed

### 3.2 — Rogue process deep-dive (PID 14771)

```
$ ps -p 14771 -o pid,ppid,user,lstart,cmd
    PID    PPID USER                      STARTED CMD
  14771    3801 root     Wed Apr  8 00:09:39 2026 node /tmp/rogue-server.js

$ ls -la /proc/14771/exe
lrwxrwxrwx 1 root root 0 → /usr/bin/node

$ cat /proc/14771/cmdline | tr '\0' ' '
node /tmp/rogue-server.js
```

| Field        | Value                       |
| ------------ | --------------------------- |
| PID          | 14771                       |
| PPID         | 3801                        |
| User         | **root**                    |
| Started      | 2026-04-08 00:09:39 EAT     |
| Command      | `node /tmp/rogue-server.js` |
| Binary       | `/usr/bin/node`             |
| Listening on | 127.0.0.1:3001              |

**Assessment:** This is **not** the legitimate kk-api service. It runs as `root` (kk-api should run as user `kk-api`), executes from `/tmp/` (kk-api runs from `/opt/kijanikiosk/api/`), and started at 00:09 — the same timestamp as the payment log files. It is a rogue process squatting on the kk-api port.

### 3.3 — HTTP response test on port 3001

```
$ curl -sv --max-time 3 http://localhost:3001/
< HTTP/1.1 500 Internal Server Error
< Content-Type: application/json
{"error":"Internal Server Error","service":"unknown"}
```

**Finding:** The process returns a **500 with `"service":"unknown"`**. This is not a kk-api response — it's a rogue server that unconditionally returns 500 errors. Any health check or upstream proxy hitting this port would see constant failures.

Source of the rogue server (`/tmp/rogue-server.js`):

```js
const http = require('http');
const server = http.createServer((req, res) => {
	res.writeHead(500, { 'Content-Type': 'application/json' });
	res.end(
		JSON.stringify({ error: 'Internal Server Error', service: 'unknown' }),
	);
});
server.listen(3001, '127.0.0.1', () => {
	console.log('Rogue server listening on 127.0.0.1:3001');
});
```

### 3.4 — Firewall rules (ufw status numbered)

```
     To                         Action      From
     --                         ------      ----
[ 1] 22/tcp                     ALLOW IN    Anywhere
[ 2] 80/tcp                     ALLOW IN    Anywhere
[ 3] 3001/tcp                   DENY IN     Anywhere         # MISCONFIGURED: blocks health checks
[ 4] 22/tcp (v6)                ALLOW IN    Anywhere (v6)
[ 5] 80/tcp (v6)                ALLOW IN    Anywhere (v6)
[ 6] 3001/tcp (v6)              DENY IN     Anywhere (v6)    # MISCONFIGURED: blocks health checks
```

**Expected rules (from Wednesday provisioning):** ALLOW 22/tcp, ALLOW 80/tcp, default deny incoming. That's it.

**Anomaly:** Rules **[3]** and **[6]** — `DENY IN 3001/tcp` — were **not** part of the provisioning script. These explicitly block any external health check or monitoring agent from reaching the kk-api port. The comment `MISCONFIGURED: blocks health checks` was left in the rule itself. Even after killing the rogue server and starting the real kk-api, external health checks would still fail due to this deny rule.

### 3.5 — External interface test

```
$ curl -sv --max-time 3 http://192.168.8.19:3001/
* connect to 192.168.8.19 port 3001 failed: Connection refused
```

**Finding:** Port 3001 is unreachable from the external interface. This is caused by **two layers of blocking**: (1) the rogue process only binds to `127.0.0.1`, not `0.0.0.0`, and (2) ufw rule [3] denies 3001/tcp inbound anyway. Even if the legitimate kk-api bound to `0.0.0.0:3001`, the firewall would still reject external connections.

---

## Confirmed Faults (Three identified)

| #     | Fault                                                                                                                 | Evidence                                                                           |
| ----- | --------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| **1** | 1.6 GB of binary-data fake logs in `/opt/kijanikiosk/shared/logs/` with no logrotate config                           | `du -sh` → 1.6G; `file` → `data` (random bytes); no `/etc/logrotate.d/kijanikiosk` |
| **2** | Rogue Node.js process (PID 14771, root, `/tmp/rogue-server.js`) squatting on port 3001, returning 500 to all requests | `ss -tlnp`; `ps -p 14771`; `curl localhost:3001` → `{"service":"unknown"}`         |
| **3** | UFW deny rules [3]/[6] blocking port 3001/tcp inbound, preventing external health checks                              | `ufw status numbered` → `DENY IN 3001/tcp # MISCONFIGURED`                         |

**Bonus finding:** nginx is failed because apache2 holds port 80. This pre-dates the injected faults but compounds the service impact.

---

## Phase 4: Remediation

### Fix Order Rationale

1. **Port conflict first** — fastest fix with the most immediate impact on the 502 error rate. Killing the rogue process frees port 3001 so the legitimate kk-api can bind.
2. **Firewall second** — restores health check visibility so the load balancer can resume routing traffic to this node.
3. **Log rotation third** — addresses the underlying cause of I/O saturation and prevents recurrence.

**Why this order matters — false-positive health status risk:**
If the firewall deny rule were removed _before_ killing the rogue process, the monitoring system's health probe would gain network access to port 3001. However, the rogue server (bound to 127.0.0.1:3001) would still intercept loopback requests and return `HTTP 500 {"service":"unknown"}`. Depending on whether the health check probes from the loopback or the external interface, outcomes differ:

- **External probe:** Would get `Connection refused` (rogue binds only to 127.0.0.1, not 0.0.0.0) — so the health check would still fail. Not a false positive in this specific case, but an unnecessary exposure window.
- **Loopback probe (e.g., nginx upstream check):** Would reach the rogue server and get 500 errors — still unhealthy, but now the path is open for confusion.
- **If an operator reconfigured the rogue to bind 0.0.0.0:** The health check would reach the rogue server on the external interface, see a 200-less response, and a poorly configured load balancer that only checks "did TCP connect succeed" could mark the node healthy — sending real user traffic to a server that returns 500 on every request.

The safe sequence is: kill rogue → remove deny rule → fix logs. Each fix is independently verifiable before proceeding to the next.

---

### Fix 1: Port Conflict — Kill Rogue Process

**Process state check (determines signal choice):**

```
$ ps -p 14771 -o pid,stat,user,cmd
    PID STAT USER     CMD
  14771 Sl   root     node /tmp/rogue-server.js
```

State is `Sl` (sleeping, multi-threaded) — **not** `D` (uninterruptible sleep). SIGTERM is appropriate because the process can receive and handle the signal. SIGKILL would risk leaving the TCP socket in TIME_WAIT and any file handles uncleaned.

**Signal sent: SIGTERM (15)**

```
$ sudo kill -15 14771
SIGTERM sent, waiting 5 seconds...

$ ps -p 14771 -o pid,stat,cmd
    PID STAT CMD
(no output — process has exited)

$ sudo ss -tlnp | grep 3001
(no listener on 3001 — port is free)
```

**Cleanup:**

```
$ sudo rm -v /tmp/rogue-server.js /tmp/rogue-server.log
removed '/tmp/rogue-server.js'
removed '/tmp/rogue-server.log'
```

**Verification:** Port 3001 is now free. The rogue process exited cleanly on SIGTERM (no escalation to SIGKILL needed). Artifacts removed from `/tmp/`.

---

### Fix 2: Firewall — Remove Erroneous Deny Rules

**Before:**

```
     To                         Action      From
[ 1] 22/tcp                     ALLOW IN    Anywhere
[ 2] 80/tcp                     ALLOW IN    Anywhere
[ 3] 3001/tcp                   DENY IN     Anywhere         # MISCONFIGURED: blocks health checks
[ 4] 22/tcp (v6)                ALLOW IN    Anywhere (v6)
[ 5] 80/tcp (v6)                ALLOW IN    Anywhere (v6)
[ 6] 3001/tcp (v6)              DENY IN     Anywhere (v6)    # MISCONFIGURED: blocks health checks
```

**Commands (delete higher-numbered rule first to preserve indices):**

```
$ sudo ufw delete 6    # v6 deny 3001/tcp
Rule deleted (v6)

$ sudo ufw delete 3    # v4 deny 3001/tcp
Rule deleted
```

**After:**

```
Status: active
Logging: on (low)
Default: deny (incoming), allow (outgoing), deny (routed)

To                         Action      From
22/tcp                     ALLOW IN    Anywhere
80/tcp                     ALLOW IN    Anywhere
22/tcp (v6)                ALLOW IN    Anywhere (v6)
80/tcp (v6)                ALLOW IN    Anywhere (v6)
```

**Verification:** Ruleset now matches the expected provisioning baseline (22/tcp + 80/tcp only, default deny incoming). Port 3001 is governed by the default deny policy — external access requires an explicit ALLOW if needed; internal (loopback) access is unaffected by ufw.

---

### Fix 3: Log Accumulation — Rotation, Cleanup, and Provisioning Update

**Before:**

```
Filesystem      Size  Used Avail Use%
/dev/nvme0n1p2  468G   45G  399G  11%

/opt/kijanikiosk/shared/logs/: 1.6G
payments-2024-03-10.log  512M  (binary data, not real logs)
payments-2024-03-14.log  512M  (binary data, not real logs)
payments-2024-03-17.log  512M  (binary data, not real logs)

/etc/logrotate.d/kijanikiosk: does not exist
```

**Step 1 — Create logrotate config:**

```
$ sudo tee /etc/logrotate.d/kijanikiosk
/opt/kijanikiosk/shared/logs/*.log {
    su kk-logs kijanikiosk
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0660 kk-logs kijanikiosk
    sharedscripts
    postrotate
        systemctl reload kk-api.service 2>/dev/null || true
    endscript
}
```

Key decisions:

- `su kk-logs kijanikiosk` — required because the logs directory is SGID 2770 (group-writable, not root-owned). Without this directive, logrotate refuses to operate on files in group-writable directories.
- `daily` with `rotate 14` — 14-day retention. On a production system with ~10 MB/day of real logs, this caps disk usage at ~140 MB (plus one uncompressed via `delaycompress`).
- `create 0660 kk-logs kijanikiosk` — new log files match the ACL-based ownership model from the provisioning script.

**Step 2 — Force immediate rotation:**

```
$ sudo logrotate --force /etc/logrotate.d/kijanikiosk
(exit code 0)
```

**Step 3 — Remove rotated fake binary files:**

```
$ sudo rm /opt/kijanikiosk/shared/logs/payments-*.log.1
```

**After:**

```
Filesystem      Size  Used Avail Use%
/dev/nvme0n1p2  468G   44G  401G  10%

/opt/kijanikiosk/shared/logs/: 8.0K
payments-2024-03-10.log  0  (empty, fresh)
payments-2024-03-14.log  0  (empty, fresh)
payments-2024-03-17.log  0  (empty, fresh)
```

**Disk reclaimed:** 1.6 GB freed (45G → 44G used, 399G → 401G available).

**Idempotency test:**

```
$ sudo logrotate --force /etc/logrotate.d/kijanikiosk
exit code: 0
(no errors, runs cleanly on second invocation)
```

**Step 4 — Provisioning script updated:**

Added `provision_logrotate()` function to `week3/wednesday/kijanikiosk-provision.sh` that:

- Writes the same `/etc/logrotate.d/kijanikiosk` config shown above
- Validates the config with `logrotate --debug` (dry-run)
- Is called in `main()` between `provision_firewall` and `verify_state`
- Added logrotate config existence check to `verify_state()`

This ensures any newly provisioned server gets log rotation from day one — the fault that allowed 1.6 GB of unrotated logs cannot recur.

---

## Phase 5: Post-Remediation Verification

**Timestamp:** 2026-04-08 01:57:56 EAT

### 5.1 — Performance: vmstat 2 5

```
procs -----------memory---------- ---swap-- -----io---- -system-- -------cpu-------
 r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st gu
 2  0      0 7314940 176848 3804236    0    0   360   389 2464    3  2  1 97  0  0  0
 0  0      0 7328968 176888 3788064    0    0     0   110 3981 12491  5  1 93  0  0  0
 0  0      0 7326812 176920 3785608    0    0     0    98 3153 4704  3  1 96  0  0  0
 2  0      0 7321724 176920 3787444    0    0     0    10 3045 4699  3  1 95  0  0  0
 0  0      0 7328236 176920 3773292    0    0     0     0 4637 6503  5  1 93  0  0  0
```

| Check         | Result                   | Pass?                       |
| ------------- | ------------------------ | --------------------------- |
| wa (I/O wait) | 0% across all 5 samples  | **PASS** (threshold: < 10%) |
| b (blocked)   | 0 across all 5 samples   | **PASS**                    |
| si/so (swap)  | 0/0 across all 5 samples | **PASS**                    |

### 5.2 — Disk: space recovered

```
$ df -h /
Filesystem      Size  Used Avail Use%
/dev/nvme0n1p2  468G   44G  401G  10%

$ du -sh /opt/kijanikiosk/shared/logs/
8.0K
```

| Check           | Before    | After     | Pass?                       |
| --------------- | --------- | --------- | --------------------------- |
| Filesystem Used | 45G (11%) | 44G (10%) | **PASS** — 1.6 GB reclaimed |
| Log dir size    | 1.6G      | 8.0K      | **PASS**                    |

### 5.3 — Network: port 3001 state

```
$ sudo ss -tlnp | grep 3001
(no listener on port 3001)
```

| Check                 | Result             | Pass?    |
| --------------------- | ------------------ | -------- |
| Rogue process on 3001 | Gone — no listener | **PASS** |

**Note:** The legitimate `kk-api.service` is not currently listening because the application code (`/opt/kijanikiosk/api/server.js`) has not been deployed. The service unit is enabled but failed with `Result: resources` after exhausting its restart limit (`StartLimitBurst=5`) while the rogue process still held the port. After deploying the application code, running `systemctl reset-failed kk-api && systemctl start kk-api` will bring the service up.

### 5.4 — Firewall: deny rule removed

```
$ sudo ufw status numbered
     To                         Action      From
[ 1] 22/tcp                     ALLOW IN    Anywhere
[ 2] 80/tcp                     ALLOW IN    Anywhere
[ 3] 22/tcp (v6)                ALLOW IN    Anywhere (v6)
[ 4] 80/tcp (v6)                ALLOW IN    Anywhere (v6)
```

| Check                         | Result                     | Pass?    |
| ----------------------------- | -------------------------- | -------- |
| DENY 3001/tcp rule            | Absent                     | **PASS** |
| Matches provisioning baseline | Yes (22/tcp + 80/tcp only) | **PASS** |

### 5.5 — Service health: curl localhost:3001

```
$ curl -s --max-time 3 http://localhost:3001/
curl: (7) Failed to connect to localhost port 3001 after 0 ms: Couldn't connect to server
```

**Expected behavior:** Connection refused is correct — port 3001 is free and waiting for the legitimate kk-api deployment. The rogue 500 response is gone.

### 5.6 — Journal: no new errors

```
$ journalctl -u kk-payments -p err --since "5 minutes ago"
-- No entries --

$ journalctl -u kk-api -p err --since "5 minutes ago"
-- No entries --
```

| Check                  | Result | Pass?    |
| ---------------------- | ------ | -------- |
| New kk-payments errors | None   | **PASS** |
| New kk-api errors      | None   | **PASS** |

### 5.7 — Logrotate config: present and valid

```
$ cat /etc/logrotate.d/kijanikiosk
/opt/kijanikiosk/shared/logs/*.log {
    su kk-logs kijanikiosk
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0660 kk-logs kijanikiosk
    sharedscripts
    postrotate
        systemctl reload kk-api.service 2>/dev/null || true
    endscript
}
```

| Check             | Result            | Pass?    |
| ----------------- | ----------------- | -------- |
| Config exists     | Yes               | **PASS** |
| Frequency         | daily             | **PASS** |
| Retention         | 14 days           | **PASS** |
| Idempotent re-run | exit 0, no errors | **PASS** |

### Verification Summary

| #   | Check                                                 | Status   |
| --- | ----------------------------------------------------- | -------- |
| 1   | I/O wait < 10%, no blocked processes                  | **PASS** |
| 2   | Disk space recovered (1.6G → 8K in log dir)           | **PASS** |
| 3   | Port 3001 free of rogue process                       | **PASS** |
| 4   | UFW deny rules removed, matches provisioning baseline | **PASS** |
| 5   | No 500 response on port 3001                          | **PASS** |
| 6   | No new journal errors                                 | **PASS** |
| 7   | Logrotate config present, daily, 14-day retention     | **PASS** |

**All seven verification checks pass.** The three injected faults have been fully remediated.

---

## Root Causes

### Fault 1: Disk I/O Saturation via Log Accumulation

Three files (`payments-2024-03-10.log`, `payments-2024-03-14.log`, `payments-2024-03-17.log`) totalling 1.6 GB were written to `/opt/kijanikiosk/shared/logs/`. They contained raw binary data (`/dev/urandom`), not real log entries. No logrotate configuration existed, so nothing prevented unbounded growth.

**Contribution to 502 errors:** On a resource-constrained server (cloud VM with limited IOPS), the 1.5 GB of writes would saturate the disk I/O budget. Any service writing logs, database WAL segments, or temporary files to the same filesystem would experience elevated write latency. Applications with I/O timeouts would begin failing requests, manifesting as upstream 502/504 errors through the reverse proxy.

### Fault 2: Port Conflict via Rogue Process

A Node.js process (`node /tmp/rogue-server.js`, PID 14771, running as `root`) bound to `127.0.0.1:3001` — the port reserved for the `kk-api.service`. The rogue server returned `HTTP 500 {"error":"Internal Server Error","service":"unknown"}` to every request.

**Contribution to 502 errors:** Two impacts: (a) The legitimate kk-api service could not bind to port 3001 and exhausted its systemd restart limit (`StartLimitBurst=5`), entering a failed state. (b) Any internal proxy or health check hitting `localhost:3001` received 500 errors from the rogue server, which the reverse proxy would surface as 502 Bad Gateway to clients.

### Fault 3: Firewall Misconfiguration

UFW rules `DENY IN 3001/tcp` (IPv4 rule [3] and IPv6 rule [6]) were added with the comment `MISCONFIGURED: blocks health checks`. These were not part of the Wednesday provisioning baseline.

**Contribution to 502 errors:** Even after resolving faults 1 and 2, external health checks and monitoring probes could not reach port 3001. A load balancer would mark this node as permanently unhealthy and stop routing traffic to it — effectively a self-imposed denial of service. Internal (loopback) traffic was unaffected by UFW, but external monitoring and health checks were completely blocked.

---

## Prevention

| Fault                             | Recurrence Prevention                             | Implementation                                                                                                                                                                                                                                                                     |
| --------------------------------- | ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **1 — Log accumulation**          | Logrotate config provisioned automatically        | `provision_logrotate()` added to `kijanikiosk-provision.sh`: writes `/etc/logrotate.d/kijanikiosk` with `daily`, `rotate 14`, `compress`. Verified by `verify_state()`.                                                                                                            |
| **2 — Rogue process**             | Monitor for unexpected listeners on service ports | (a) Add a `verify_state()` check that confirms only expected processes are on ports 3001/80. (b) `ProtectSystem=strict` + `NoNewPrivileges=true` in the kk-api unit prevent the service itself from spawning rogue children. (c) Periodic `ss -tlnp` audit in monitoring/alerting. |
| **3 — Firewall misconfiguration** | Provisioned firewall resets to baseline           | `provision_firewall()` already runs `ufw --force reset` before applying rules, which removes any manually-added deny rules. Add a comment in the function: `# WARNING: Do not add deny rules for service ports (3001) — this blocks health checks.`                                |

### Operational Recommendations

1. **Alert on disk usage:** Set a monitoring threshold at 80% filesystem usage on the application volume. The 1.6 GB of fake logs grew unchecked because there was no alert.
2. **Alert on unexpected port listeners:** A scheduled check (`ss -tlnp | diff - expected-ports.txt`) would have caught the rogue process immediately.
3. **Immutable firewall baseline:** Store the expected UFW ruleset in version control and run a compliance check on each provisioning run.
4. **kk-api systemd hardening:** The existing `StartLimitBurst=5` / `StartLimitIntervalSec=300` prevented infinite restart loops, which is good. After remediation, `systemctl reset-failed kk-api` is needed to clear the failed state.

---

## Timeline

| Time (EAT) | Event                                                                                                                                    |
| ---------- | ---------------------------------------------------------------------------------------------------------------------------------------- |
| 00:09      | Faults injected (3 × 512MB log writes, rogue server started, UFW deny added)                                                             |
| 00:20:08   | Investigation started — Phase 1 (Performance Layer)                                                                                      |
| 00:30      | Phase 1 hypothesis written: disk I/O contention + suspicious port 3001 listener                                                          |
| ~00:35     | Phase 2 (Log Layer): nginx found down, no kk-payments unit, fake binary logs confirmed, no logrotate config                              |
| 00:50      | Revised hypothesis: three faults (disk + rogue process + expected firewall issue)                                                        |
| ~00:55     | Phase 3 (Network Layer): rogue process identified (root, /tmp/rogue-server.js), UFW deny confirmed, external port blocked                |
| ~01:30     | Phase 4: Fix 1 (SIGTERM rogue PID 14771), Fix 2 (delete UFW rules [6],[3]), Fix 3 (logrotate config + forced rotation + 1.6GB reclaimed) |
| ~01:45     | Provisioning script updated with `provision_logrotate()`                                                                                 |
| 01:57:56   | Phase 5: All 7 verification checks pass                                                                                                  |
