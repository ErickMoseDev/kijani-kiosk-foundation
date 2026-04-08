# KijaniKiosk Production Security Decisions

**Prepared for:** Nia (CTO) | **Date:** Week 3, Friday | **Author:** Erick Mong'are

---

## Summary

KijaniKiosk processes payment transactions across East African kiosk networks. A breach of this system exposes customer financial data, damages partner trust, and triggers regulatory reporting obligations. This document explains the security controls we applied to the production server, what risk each control addresses, and where gaps remain.

## Approach

We designed security in layers. No single control protects the system on its own. Instead, each control removes one category of attack so that an attacker who bypasses one barrier still faces several others. Every control was tested to confirm it does not break the application. Two controls we investigated were deliberately excluded because they would have caused service outages without proportional security benefit.

## What We Protected and Why

The payments service handles the most sensitive data and received the strictest controls. The API service and the logging service received a strong but slightly less restrictive profile, because they do not directly process financial data. All three services run under dedicated accounts that have no login shell, no home directory, and no ability to escalate privileges.

The firewall was rebuilt from a clean baseline rather than layered on top of four days of manual changes. Every rule has a documented purpose. The payments port is blocked from external networks entirely and is only reachable through the reverse proxy on the same machine. A specific monitoring subnet is allowed to reach the health check endpoint so that the operations team can verify service availability without opening the port to the internet.

Log files rotate daily and are retained for fourteen days. This ensures disk space is never exhausted by runaway logging, which was the root cause of a performance incident earlier this week. The logging service owns the log directory, and the other two services write to it through inherited permissions that survive log rotation without manual intervention.

Configuration files are owned by a privileged account and made readable to the application group but not writable. This prevents a compromised service from altering its own configuration to disable security controls or redirect traffic.

| Control                                        | What It Does                                                                    | Risk Mitigated                                                                                                 |
| ---------------------------------------------- | ------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Dedicated service accounts with no login shell | Each service runs as its own identity with no interactive access                | A compromised service cannot be used to log into the server or pivot to other services                         |
| Empty capability bounding set                  | Removes all elevated operating system privileges from service processes         | An attacker who gains code execution inside a service cannot escalate to administrator access                  |
| Read-only system filesystem                    | The service can only write to its designated log directory, nothing else        | Prevents malware from modifying system files, installing backdoors, or tampering with other applications       |
| Private temporary directories                  | Each service gets an isolated temporary workspace invisible to other processes  | Blocks cross-service data leakage through shared temporary storage, a common lateral movement technique        |
| Firewall with intent-based rules               | Only the required ports are open, each with a documented business justification | Eliminates exposure of internal service ports to the internet; limits the attack surface to only the web proxy |
| Payments network isolation                     | The payments service can only communicate over the local machine interface      | Even if the firewall is misconfigured, the payments service rejects all connections from external networks     |
| Log rotation with access model integration     | Logs rotate daily and new files inherit the correct permissions automatically   | Prevents disk exhaustion from unbounded log growth and ensures monitoring continuity after rotation            |
| Journal persistence with size cap              | System event logs survive reboots and are capped at a fixed storage limit       | Enables post-incident investigation while preventing log storage from consuming all available disk space       |

## What This Does Not Protect Against

These controls harden the server and its services. They do not protect against vulnerabilities in the application code itself. If the Node.js application has a flaw that allows an attacker to read payment data through a normal request, none of these operating system controls will detect or prevent that. Application-level security testing, dependency scanning, and encrypted storage of sensitive data at rest are the next investments required. Additionally, this configuration does not include intrusion detection, centralized log forwarding, or automated alerting. An attacker who operates within the permissions granted to a service account could exfiltrate data at a slow rate without triggering any current control. Network-level monitoring and anomaly detection would address this gap.
