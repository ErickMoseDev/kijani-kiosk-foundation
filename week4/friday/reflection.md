# Week 4 Friday Reflection

## 1. Where Two Requirements Conflicted

The conflict showed up when I was wiring the Ansible playbook to the Week 3 systemd hardening. The requirement said to deploy environment files for each service using Ansible templates. The Week 3 hardening requirement said kk-payments must run with `ProtectSystem=strict`, which makes most of the filesystem read-only to the service process.

If I had placed the env files under `/etc/`, `ProtectSystem=strict` would have made them unreadable at runtime because that path becomes read-only for the sandboxed process. The fix was to keep `EnvironmentFile` pointing to `/opt/kijanikiosk/config/`, which is already under `ReadOnlyPaths` in the unit file. systemd reads the EnvironmentFile as PID 1 before sandboxing kicks in, so it works regardless, but `ReadOnlyPaths` also lets the process read its own config at runtime if it needs to.

What I learned: when two layers of automation touch the same resource (Ansible writing a file, systemd restricting access to it), you have to trace the full lifecycle of that file. It is not enough to know that the file exists. You need to know who reads it, at what stage of the process, and under what restrictions.

## 2. One Sentence Rewritten for Tendo

**For Nia (original):**
"Network access is controlled at two boundaries. The cloud provider's firewall restricts which traffic can reach each server before a single packet touches the operating system."

**For Tendo (rewritten):**
"Each EC2 instance gets a per-module `aws_security_group` with ingress rules scoped to port 22 from `var.my_ip_address` and port 80 from `0.0.0.0/0`. No service ports (3000, 3001, 5000) are exposed in the security group; they are only reachable via the nginx reverse proxy on localhost."

**What is lost:** Nia's version communicates the _why_ and the layered defense strategy. A non-technical reader understands that there are two checkpoints and that one operates before the other. The business risk is clear.

**What is gained:** Tendo's version is auditable. He can open the Terraform module, find the exact resource, and verify the claim in thirty seconds. He can also spot if the implementation drifts from the intent, for example if someone later adds a rule exposing port 3001. Nia's version would never surface that kind of regression.

## 3. The Most Fragile Handoff

The most fragile point is the Terraform-to-Ansible handoff in `pipeline.sh`, specifically the line:

```
terraform output -raw ansible_inventory > inventory.ini
```

This works because the `ansible_inventory` output in `outputs.tf` hardcodes the host aliases (`api-staging`, `payments-staging`, `logs-staging`) and the `host_vars/` filenames match those exact aliases. If the Terraform module's `for_each` keys change, or someone adds a fourth server, or the environment name shifts from staging to production, the output generates inventory hostnames that do not match any `host_vars/` file. Ansible would then apply the playbook with undefined variables and either fail or silently skip the host-specific configuration.

To make this handoff robust in a real production environment, I would need to know: how many servers exist per environment, whether host aliases follow a predictable naming convention, and whether `host_vars/` files are generated dynamically or maintained by hand. The fix would be to either generate `host_vars/` from Terraform as well, or use a dynamic inventory script that queries the Terraform state directly instead of writing a static file.
