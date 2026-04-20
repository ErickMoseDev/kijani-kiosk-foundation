# KijaniKiosk Week 4 Security Decisions: Infrastructure as Code

**Prepared for:** Nia (CTO) | **Date:** Week 4, Friday | **Author:** Erick Mong'are

---

## Summary

This week we moved KijaniKiosk's infrastructure from manually provisioned servers to a fully automated pipeline. Every server, firewall rule, and service configuration is now defined in code, reviewed before deployment, and applied identically every time. This document explains the security controls embedded in that pipeline, what risk each one addresses, and where gaps remain.

## Why Automation Changes the Security Posture

Last week's hardening was applied by hand. That approach worked for three servers, but it introduced a risk that no individual control can solve: drift. When a human applies security settings manually, each server accumulates small differences over time. A firewall rule gets added during troubleshooting and never removed. A file permission is relaxed to debug an issue and never tightened. Within weeks, the servers that were supposed to be identical are not.

By defining infrastructure in code, we eliminate configuration drift. The pipeline provisions servers, extracts their network addresses, writes them into the configuration management inventory, and applies the full hardening profile. Running the pipeline a second time produces zero changes, which is proof that the desired state and the actual state match. If someone modifies a server manually, the next pipeline run corrects the deviation automatically.

## How the Infrastructure Layer Protects the Platform

The provisioning layer controls which servers exist, what network they sit on, and who can reach them. Each server is created from the same base image, in the same region, with the same hardware profile. This means a vulnerability found on one server can be assessed and patched across all three with certainty the environments are equivalent.

Network access is controlled at two boundaries. The cloud provider's firewall restricts which traffic can reach each server before a single packet touches the operating system. Administrative access is limited to a single operator address. Web traffic is permitted from the public internet on the standard web port only. No application service port is exposed directly. The state file recording what infrastructure exists is stored encrypted with locking to prevent conflicting simultaneous changes, protecting against both accidental destruction and unauthorized inspection of infrastructure details.

## How the Server Layer Protects Each Service

Once a server exists, the configuration management layer applies the same hardening profile validated last week, but now as code that can be reviewed, versioned, and audited. Each service runs under a dedicated identity with no ability to log in interactively. The operating system filesystem is mounted read-only for every service process, with explicit exceptions only for the shared log directory. Each service receives isolated temporary storage invisible to other processes. Kernel interfaces that services have no legitimate reason to access are blocked.

The payments service receives the strictest profile because it processes financial data. All three services load configuration from a directory readable by the application group but not writable by any service. A compromised service cannot alter its own configuration to disable protections or redirect traffic. Environment-specific values are generated from templates and deployed with permissions matching the access model. The pipeline writes these files once, and subsequent runs verify they have not been altered.

## Control Summary

| Control                                      | What It Does                                                                      | Risk Mitigated                                                                                 |
| -------------------------------------------- | --------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------- |
| SSH restricted to operator address           | Cloud firewall rejects administrative connections from all other sources          | Eliminates brute-force attacks against the management interface from the open internet         |
| No direct application port exposure          | Only the web proxy port is open publicly; service ports are internal only         | Attackers cannot reach application services directly, even if a code vulnerability exists      |
| Encrypted remote state with locking          | Infrastructure definitions are stored encrypted with concurrent-access protection | Prevents unauthorized reading of infrastructure details and conflicting simultaneous changes   |
| Key pair managed outside the pipeline        | Authentication credential referenced by name, never embedded in code              | Eliminates private key exposure through version control or pipeline logs                       |
| Dedicated service accounts with no shell     | Each service runs as its own identity with no interactive login                   | A compromised service cannot be used to log in or pivot laterally to other services            |
| Read-only filesystem for all services        | Service processes cannot write anywhere except the designated log directory       | Prevents backdoor installation, system file modification, or tampering with other applications |
| Private temporary directories per service    | Each process gets an isolated temporary workspace invisible to others             | Blocks cross-service data leakage through shared temporary storage                             |
| Empty capability bounding set                | All elevated operating system privileges removed from service processes           | An attacker with code execution inside a service cannot escalate to administrator access       |
| Configuration files not writable by services | Environment files owned by a privileged account, readable by group only           | A compromised service cannot modify its own settings to disable controls or exfiltrate secrets |
| Automated pipeline with idempotent runs      | Full provisioning and hardening execute as a single repeatable operation          | Eliminates configuration drift and guarantees every run produces a known-good state            |

## What This Posture Does Not Protect Against

The controls described above secure the infrastructure and operating system layers. They do not inspect the application code running inside each service. A vulnerability in the business logic (an endpoint that returns payment data without proper authorization, a dependency with a known exploit, or a query manipulated to extract records beyond the caller's scope) will succeed within the permissions already granted to the service account. The pipeline does not include secrets rotation; the payments API key is deployed from a template but never automatically cycled. There is no intrusion detection, no centralized log forwarding, and no automated alerting. An attacker operating slowly within a service's normal permissions could exfiltrate data without triggering any current control. Application security testing, dependency scanning, secrets management, and network-level anomaly detection are the necessary next investments.
