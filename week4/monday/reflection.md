# Week 4 Monday: Reflection

## Question 1: The Idempotency Gap

The Week 3 provisioning script achieved idempotency by checking current state before every action. For example: `id kk-api >/dev/null || useradd kk-api`, `[[ ! -f /etc/apt/sources.list.d/nodesource.list ]]`, `getent group kijanikiosk || groupadd kijanikiosk`. Every operation was wrapped in a guard condition that said "if this already exists, skip it." The script had to encode both the desired state and the logic to detect current state in every single line.

Terraform achieves idempotency through a completely different mechanism: the **state file**. When you run `terraform apply`, Terraform does not scan the infrastructure to figure out what exists. Instead, it reads `terraform.tfstate`, a JSON file that records every resource Terraform has created, including their IDs, attributes, dependencies, and current property values. Terraform compares three things: the desired state in your `.tf` files, the recorded state in `terraform.tfstate`, and (via a refresh) the actual state of the infrastructure as reported by the cloud provider API.

The decision logic works like this: if a resource is in the config but not in the state file, Terraform creates it. If a resource is in both the config and the state file but the attributes differ, Terraform updates it (or destroys and recreates it if the change is destructive). If a resource is in the state file but not in the config, Terraform destroys it. If the config and state file match, Terraform does nothing. No guard conditions are needed because the state file _is_ the guard.

Here is a divergence scenario: suppose someone logs into the AWS console and manually changes the security group to allow port 443, or deletes a subnet. The state file still says the old configuration is in place. On the next `terraform plan`, Terraform refreshes actual state from the API and detects the drift. If the manual change contradicts the config, Terraform will revert it. If a resource was deleted outside of Terraform, Terraform will recreate it. The correct response to state drift is to run `terraform plan` to detect it, then either: (a) run `terraform apply` to enforce the declared config and overwrite the manual change, or (b) if the manual change was intentional, update the `.tf` files to match and run `terraform apply` so the config, state, and reality all agree. You should never edit the state file by hand.

## Question 2: Declarative Specification Quality

Looking at my `desired-state-spec.md`, there are real gaps that would block another engineer from reproducing this exactly.

**Gap 1: SSH source IP is unspecified.** The spec says "source [your IP]/32 only" without an actual IP address or CIDR range. If Terraform tried to fill this gap, it would either fail (no default exists for a CIDR input variable) or, worse, someone might set it to `0.0.0.0/0` as a workaround, which opens SSH to the entire internet. A different engineer reading this spec would have to ask "whose IP?" before they could write the security group rule.

**Gap 2: No availability zone is specified.** The spec says region `af-south-1` and references a specific subnet, but it doesn't declare which availability zone the instance should land in. Terraform would place it in whatever AZ the subnet belongs to. But if a different engineer created a new subnet instead of reusing the one I referenced, they would have to pick an AZ, and their choice might affect latency, cost, or high-availability design. The spec assumes you will use my exact subnet ID, which is a hardcoded artifact of my specific account, not a reproducible specification.

**Gap 3: No application software or configuration is specified.** The spec covers the VM and its network posture but says nothing about what runs on the server. There is no mention of Node.js, nginx, service accounts, or application deployment. An engineer could reproduce the infrastructure shell perfectly and still have no idea what to put on it.

This reveals that specification quality directly determines automation reliability. If the spec is ambiguous, the automation either fails at plan time (best case) or silently makes assumptions that produce infrastructure that looks right but behaves wrong. Every "open question" in the spec is a place where two engineers would produce different infrastructure from the same document.

## Question 3: Tool Boundary

**Creating a firewall rule that allows port 80 from anywhere: Terraform.**
This is infrastructure state, specifically an AWS security group ingress rule. It exists at the cloud provider level, has an API-managed lifecycle, and should be versioned and tracked in state alongside the instance it protects. If you used Ansible for this, you would have a firewall rule that exists but is not tracked in Terraform state. A future `terraform apply` would not know about it, and might create a conflicting rule or fail to destroy it on teardown. If you used bash, you would have no state tracking at all and no way to detect drift.

**Installing nginx 1.24.0 on a running VM: Ansible.**
This is configuration management: a package that needs to be installed, version-pinned, and kept consistent across the fleet. Ansible's `apt` module handles idempotent package installation natively. You could do this in Terraform using a `provisioner "remote-exec"` block or `user_data`, but that only runs at instance creation time. If the package gets removed or upgraded later, Terraform will not detect or fix it because Terraform does not manage the internal state of a VM. Bash could do it (and our Week 3 script did), but you would have to write all the guard conditions yourself and have no built-in mechanism to re-run it when the state drifts.

**Verifying that nginx is responding to HTTP requests after installation: Bash.**
This is a runtime validation check, a one-time assertion that the system is working. Something like `curl -s -o /dev/null -w '%{http_code}' http://localhost` returning `200`. Ansible has `uri` and `wait_for` modules that could do this, and that is defensible if verification is part of a larger playbook. But a simple `curl` check in a script or CI pipeline is the lightest-weight approach and does not require pulling in a configuration management tool for a single assertion. Terraform is completely wrong here because it has no concept of "verify runtime behavior" since it operates at the infrastructure layer, not the application layer.

## Question 4: From Script to Spec

The eight phases of the Week 3 provisioning script, mapped against declarative expression:

**Phases that translated cleanly:**

- **Phase 1 (Packages)**: partially clean. The "what" (nginx 1.24.0, Node.js 20) maps directly to a desired-state declaration. But the "how," like adding GPG keys, configuring the NodeSource repo, and holding packages, is procedural. Ansible handles this cleanly with its `apt` module. Terraform does not touch it at all because packages live inside the VM.
- **Phase 5 (Firewall)**: translates cleanly into Terraform security group rules. The script's `ufw allow in 80/tcp` becomes an `ingress` block. Rule ordering, which mattered in UFW, is irrelevant in a security group because AWS evaluates all rules collectively. This was the easiest phase to express declaratively.

**Phases that were difficult or impossible to express declaratively:**

- **Phase 2 (Service Accounts)**: creating `kk-api`, `kk-payments`, `kk-logs` with specific shells, group membership, and no home directories. This is entirely inside the VM. Terraform cannot express it. Ansible can, but you are describing users as resources, not as a sequence of `useradd` commands. The translation is possible but lives in a different tool.
- **Phase 3 (Directories, ACLs, Config Files)**: directory structures with specific ownership, permissions, SGID bits, and POSIX ACLs. This is highly procedural. Ansible can manage files and directories declaratively, but ACL management (`setfacl` with default entries) pushes the boundary of what Ansible handles natively. Some of this ends up as raw commands even in Ansible.
- **Phase 4 (systemd Units)**: writing unit files with 30+ hardening directives, then enabling services. Ansible's `template` and `systemd` modules can express this, but the unit file content is essentially a blob of text that gets placed on disk. The placement is declarative, but the content is a configuration artifact that cannot be generated from a higher-level abstraction.
- **Phase 6 (Dirty-State Cleanup)**: killing rogue processes, removing stale files, stopping conflicting services. This is inherently procedural and reactive. You cannot declare "no rogue processes." You can only detect and kill them. This phase has no declarative equivalent because it responds to unpredictable state, not a known-good baseline.
- **Phase 7 (Journal Persistence and Log Rotation)**: configuring journald and logrotate. Again, this is inside-the-VM configuration management. It belongs in Ansible territory, not Terraform.
- **Phase 8 (Health Checks)**: checking if services respond on their ports and writing a JSON report. This is runtime verification, not desired state. It is a bash task that asserts outcomes. No declarative tool would express "check that port 3000 answers" as a resource to be managed.

**What this tells us:** Infrastructure provisioning (the VM, its network, its firewall rules) maps naturally to declarative specifications because these are API-managed resources with clear create/update/destroy lifecycles. Configuration management (packages, users, files, services inside the VM) can be expressed declaratively but requires a different tool like Ansible that understands OS-level state. Procedural tasks like cleanup and verification resist declarative expression entirely because they respond to unpredictable runtime conditions rather than converging toward a known state. The boundary between Terraform and Ansible is essentially the boundary between "things the cloud API manages" and "things the operating system manages."
