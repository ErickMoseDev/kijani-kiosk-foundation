# Week 4 Thursday - Reflection

## Question 1: Ansible vs Bash Idempotency

In the Week 3 bash script, every operation needed a manual guard. For example, `if ! id "kk-api" >/dev/null 2>&1; then useradd ... fi`. Without that check, running the script twice would fail or create duplicate entries. The script author had to think about idempotency for every single line.

Ansible handles this differently. Each module has idempotency built into it. When you call `ansible.builtin.user` with `state: present`, the module itself checks whether the user already exists on the system before doing anything. If the user is already there with the right settings, it reports `ok` and moves on. If something is different, it makes only the needed change and reports `changed`. The playbook author never writes a guard condition because the module does all that internally.

When the `ansible.builtin.user` module runs with `state: present`, it checks: does this user exist? If yes, do the current properties (group, shell, home, comment) match what the playbook says? If everything matches, it does nothing. If something is off, it fixes just that property. It uses the system's user database (getent/passwd) to make these checks, not by running shell commands blindly.

If you used `ansible.builtin.shell: useradd kk-api` instead, the first run would work. The second run would fail with "user already exists" because `useradd` does not check first. You would have to add your own guard, like `creates:` or an `id` check in the command, which puts you right back where you were with bash. The shell module just runs whatever command you give it. It has no idea what the command does or whether it already ran.

The shell module is the wrong choice for idempotent tasks because it has no built-in understanding of the system's current state. It cannot tell Ansible "nothing changed" unless you manually wire up `changed_when` conditions. Every run looks like a change, which breaks handler notifications and makes playbook output meaningless. You lose the core benefit of Ansible: the ability to describe what you want and let the tool figure out what needs to happen.

## Question 2: Handler Behaviour Under Parallel Execution

In our playbook, the "Deploy systemd unit file" template task notifies both the "Reload systemd" and "Restart service" handlers. When the playbook runs on three hosts, host A and host B show `changed` for the template task, and host C shows `ok`.

The handler only runs on hosts where the notifying task reported `changed`. So "Restart service" runs on host A and host B, but not on host C. That is 2 times total.

Now consider two tasks that both notify the same handler, and both change on the same host. The handler still only runs once on that host. Ansible collects all notifications during the tasks phase and then runs each handler exactly once per host at the end (or when you flush). Even if five tasks all notify the same handler, it fires once.

The rule is: a handler runs once per host at the end of the play (or at a flush point), regardless of how many tasks notified it. Duplicate notifications are collapsed into one.

This prevents unnecessary restarts. If you change both a service's config file and its unit file in the same run, you do not want the service restarting twice. One restart at the end picks up all the changes at once. This is exactly what we saw in our playbook: the template task notifies both "Reload systemd" and "Restart service", but each handler runs just once per host, even though multiple config changes might happen in a single run.

## Question 3: The Terraform to Ansible Inventory Bridge

Today we created inventory.ini by hand, copying the three IPs from `terraform output`. This works but breaks every time Terraform destroys and recreates a server because the new instance gets a different IP.

**Approach 1: Use the Terraform state file directly.** You can write a dynamic inventory script that reads the Terraform state (either the local .tfstate file or the remote S3 backend) and pulls out the instance IPs. Terraform also has a built-in provisioner and there are community tools like `terraform-inventory` that parse state into Ansible inventory format. You could also use `terraform output -json` in a wrapper script that generates the inventory file before each Ansible run.

**Approach 2: Use the cloud provider's API.** AWS has an EC2 dynamic inventory plugin (`amazon.aws.aws_ec2`) that queries the AWS API directly. You configure it with filters (like tags: `Environment=staging`, `Project=kijanikiosk`) and it builds the inventory from whatever instances are currently running. It does not care about Terraform state at all.

**Tradeoffs:** The Terraform state approach is tightly coupled to your Terraform setup. If someone changes the state backend or the output names, the inventory breaks. But it is simple and does not need AWS credentials on the Ansible control machine beyond what Terraform already uses. The AWS API approach is independent of Terraform. It works even if someone launched instances manually or through a different tool. But it needs IAM permissions for EC2 describe calls, and it can be slower because it queries the API every time. It also might pick up instances you did not intend if your tag filters are not precise.

**Recommendation for KijaniKiosk (3 engineers):** I would recommend the AWS EC2 dynamic inventory plugin. With a small team, you want fewer moving parts and less manual coordination. Tag-based discovery means the inventory stays correct no matter who provisions or replaces a server. It also removes the dependency on having access to the Terraform state file, which matters when different team members run Ansible from their own machines.

## Question 4: Configuration Drift in the Ansible Model

In the Week 3 Thursday incident, someone manually changed a firewall rule on the payments server, causing 47 minutes of downtime. With Terraform, `terraform plan` would show the drift on the next run because Terraform reads the actual infrastructure state and compares it to the config.

Ansible does not have a built-in "plan" that scans for drift. It only checks state when it runs a task. If you run the playbook, each module compares the desired state to the current state for that specific resource. So if someone manually added a ufw rule, the next playbook run would re-apply the rules defined in the playbook. But here is the key difference: Ansible only manages what is in the playbook. If someone added an extra rule that the playbook does not mention, Ansible will not remove it. It does not know about it.

If an engineer manually changes ufw rules on the payments server, the next playbook run will make sure the rules defined in the playbook still exist (SSH on 22, HTTP on 80, service port on loopback). If those rules were deleted, Ansible puts them back. But if the engineer added a new rule that opens port 9999, Ansible will not touch it because the playbook says nothing about port 9999.

Terraform's model is different because Terraform tracks the full state of every resource it manages. If something changes outside of Terraform, `terraform plan` shows the difference and `terraform apply` corrects it back to the declared state. Terraform removes things that should not be there, not just adds things that are missing.

Ansible does not track state between runs. It has no state file. It does not detect additions or changes that fall outside what the playbook describes. The operational implication for KijaniKiosk is that the team cannot rely on Ansible alone to catch unauthorized changes. They need a separate process, like scheduled `--check --diff` runs or a monitoring tool, to detect drift. Without that, manual changes can silently persist until they cause a problem, exactly like the Week 3 incident.
