# KijaniKiosk Access Model — Final (Friday)

Updated from Tuesday's access model to include the health directory (Phase 8) and logrotate interaction (Phase 7).

---

## Service Accounts

| Account     | Type             | Shell             | Home         | Group Memberships        | Purpose                                                     |
| ----------- | ---------------- | ----------------- | ------------ | ------------------------ | ----------------------------------------------------------- |
| kk-api      | System (nologin) | /usr/sbin/nologin | /nonexistent | kk-api, kijanikiosk      | Runs the API service on port 3000                           |
| kk-payments | System (nologin) | /usr/sbin/nologin | /nonexistent | kk-payments, kijanikiosk | Runs the payments service on port 3001                      |
| kk-logs     | System (nologin) | /usr/sbin/nologin | /nonexistent | kk-logs, kijanikiosk     | Runs the log aggregation service; owns shared log directory |
| amina       | Regular user     | /bin/bash         | /home/amina  | amina, kijanikiosk       | Operations auditor; reads configs and logs without sudo     |

---

## Directory Access Model

| Directory / File                            | Owner:Group             | Mode | Access Mechanism | Security Reasoning                                                                                                                                                                                |
| ------------------------------------------- | ----------------------- | ---- | ---------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| /opt/kijanikiosk/api/                       | kk-api:kk-api           | 750  | Basic UGO        | Isolation: Only the API user can read/execute its own code. Group members and others have zero visibility.                                                                                        |
| /opt/kijanikiosk/payments/                  | kk-payments:kk-payments | 750  | Basic UGO        | PCI Compliance: Payments logic is strictly siloed. Even the API service cannot see into this folder. kk-payments unit has `InaccessiblePaths=/opt/kijanikiosk/api` for mutual isolation.          |
| /opt/kijanikiosk/config/                    | root:kijanikiosk        | 750  | Basic UGO        | Centralized Secrets: Root owns config files. The kijanikiosk group (all three services + amina) can read them. No service can write config.                                                       |
| /opt/kijanikiosk/config/\*.env              | root:kijanikiosk        | 640  | Basic UGO        | No Execution: Config files are never executable. 640 ensures read-only for apps via group membership, invisible to others. Each service reads its own env file via `EnvironmentFile=` in systemd. |
| /opt/kijanikiosk/shared/logs/               | kk-logs:kk-logs         | 2770 | SGID + ACL       | Aggregation: SGID ensures new files inherit the kk-logs group. Default ACLs grant kk-api and kk-payments rwx on new files. kk-logs manages rotation.                                              |
| /opt/kijanikiosk/scripts/                   | root:root               | 750  | Basic UGO        | Integrity: Only root can modify deployment scripts. No SUID bits.                                                                                                                                 |
| /opt/kijanikiosk/health/                    | kk-logs:kijanikiosk     | 750  | Basic UGO        | **NEW (Friday):** Health check output directory. kk-logs writes the JSON. The kijanikiosk group (including amina and all services) can read health status. Others have no access.                 |
| /opt/kijanikiosk/health/last-provision.json | kk-logs:kijanikiosk     | 640  | Basic UGO        | **NEW (Friday):** Written by provisioning script (as root, then chowned). Readable by kijanikiosk group for monitoring.                                                                           |

---

## ACL Details for /opt/kijanikiosk/shared/logs/

```
# getfacl /opt/kijanikiosk/shared/logs/
# owner: kk-logs
# group: kk-logs
# flags: -s-
user::rwx
user:kk-api:rwx
user:kk-payments:rwx
group::rwx
mask::rwx
other::---
default:user::rwx
default:user:kk-api:rwx
default:user:kk-payments:rwx
default:group::rwx
default:mask::rwx
default:other::---
```

### How ACLs Interact with Logrotate

The logrotate config uses:

```
create 0660 kk-logs kijanikiosk
su kk-logs kijanikiosk
```

When logrotate runs (as root via cron):

1. It rotates the existing log file (rename → compress)
2. It creates a new empty file with ownership `kk-logs:kijanikiosk` and mode `0660`
3. Because the directory has **default ACLs**, the new file **inherits** `user:kk-api:rwx` and `user:kk-payments:rwx` automatically
4. The `su kk-logs kijanikiosk` directive tells logrotate to operate as kk-logs:kijanikiosk in the SGID directory, avoiding permission errors on the group-writable directory

**Result:** After rotation, kk-api and kk-payments can still write to the new log file without any manual intervention. The access model survives rotation.

### Verification Test

```bash
# Force rotation then test write access
sudo logrotate --force /etc/logrotate.d/kijanikiosk
sudo -u kk-api touch /opt/kijanikiosk/shared/logs/test-write.tmp \
  && echo "PASS: kk-api can write after logrotate" \
  || echo "FAIL: kk-api cannot write to shared/logs"
```

---

## Health Directory Decision (Challenge B)

The health directory `/opt/kijanikiosk/health/` was not in Tuesday's model because it did not exist yet. Design decisions:

- **Writer:** The provisioning script writes as root, then `chown`s to `kk-logs:kijanikiosk`. In future, the kk-logs service itself would write periodic health checks.
- **Readers:** All members of the `kijanikiosk` group (kk-api, kk-payments, kk-logs, amina) can read health status via group permission.
- **No ACLs needed:** Unlike the shared logs directory, health is a simple read-only output. Standard UGO permissions (750 directory, 640 file) are sufficient. Only one service writes; others only read.
- **No SGID needed:** Only kk-logs writes here. There is no multi-writer scenario requiring group inheritance.
