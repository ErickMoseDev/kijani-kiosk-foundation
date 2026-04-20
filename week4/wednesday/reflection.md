# Week 4 Wednesday: Reflection

## Question 1: The Module Boundary Decision

The VM and security group were extracted into the `app_server` module because they represent a repeatable unit. Every server KijaniKiosk deploys needs an EC2 instance and a security group, so bundling them into a module lets us stamp out multiple servers with `for_each` without duplicating code. The networking resources (VPC lookup, subnet lookup) stayed in the root module because they are shared infrastructure. All three servers use the same VPC and the same subnet. It does not make sense to put these inside the module because each module call would try to look up or create the same network, which is either wasteful (repeated data source calls) or dangerous (duplicate resource creation).

It would make sense to extract networking into a separate module if the project grew to need multiple environments with different VPCs, or if different teams managed the network and the applications separately. A dedicated networking module could output VPC IDs and subnet IDs that the app_server module consumes as inputs. This creates a clean separation of concerns.

The risk of having a single module that provisions both the network and the VMs is tight coupling. If someone runs `terraform destroy -target=module.network` to tear down the networking module, the VMs would lose their VPC and subnets. The instances would still exist in AWS for a short time, but they would have no network connectivity. They could not receive traffic or be reached via SSH. Terraform would also get confused on the next plan because the VMs reference subnet and VPC IDs that no longer exist. The plan would likely fail with errors about missing resources, and you would need to destroy the VMs separately or import new networking to recover. Keeping network and compute in separate modules (or at least separate state files) prevents one team's destroy from taking down another team's resources.

## Question 2: for_each Removal Behaviour

When you add `"cache"` to the `local.servers` map and run `terraform plan`, Terraform compares the current state (which has `module.api_servers["api"]`, `module.api_servers["payments"]`, and `module.api_servers["logs"]`) with the new config (which now also includes `module.api_servers["cache"]`). Terraform sees that the three existing keys still match, so it proposes no changes for those. It only proposes to create the new resources for the `"cache"` key. When you apply, only the cache server and its security group get created. The existing three servers are untouched.

With `count`, things work differently. If you had `count = 3`, Terraform addresses resources by index: `module.api_servers[0]`, `module.api_servers[1]`, `module.api_servers[2]`. When you change to `count = 4`, Terraform adds `module.api_servers[3]` and leaves the others alone. That seems fine in this case.

But the real problem with `count` shows up when you remove a server. If you remove the second item from a list of three, `count` shifts all the indexes. What was index 2 becomes index 1, and Terraform thinks it needs to destroy and recreate those servers because the index mapping changed. With `for_each`, each server is addressed by its map key ("api", "payments", "logs"). Removing "payments" only destroys the payments server. The other two keep their keys and are not affected.

So `for_each` is safer because adding or removing a server never causes unnecessary destruction of the others. `count` can cause downtime because index shifts force Terraform to destroy and recreate servers that did not actually change.

## Question 3: State as a Team Artefact

When Amina runs `terraform apply`, Terraform acquires a lock on the DynamoDB table before making any changes. The lock entry contains the lock ID, who acquired it (Amina's identity from her AWS credentials), the operation being performed ("OperationType: apply"), and a timestamp.

If Tendo runs `terraform plan` while Amina's apply is still running, his plan will fail with a lock error. The error message will say something like "Error acquiring the state lock" and will include the Lock ID, the user who holds the lock, the operation type, and when the lock was created. This information is useful because Tendo can see exactly who is holding the lock and what they are doing. He knows to wait for Amina to finish rather than assuming something is broken.

In the crash scenario where Amina's apply provisions two of the three servers and then her laptop loses power, the state file may be partially written. The DynamoDB lock will also be left in place because Terraform never got a chance to release it.

The recovery procedure is:

1. First, run `terraform force-unlock <LOCK_ID>` to remove the stale lock from DynamoDB. You can find the lock ID from the error message that appears when anyone tries to run a Terraform command.
2. Next, run `terraform plan` to see what Terraform thinks the current state is. Because the state file was not fully written, it might only show one or two of the three servers.
3. If the state is missing resources that actually exist in AWS, use `terraform import` to bring them back into state.
4. If the state shows resources that failed to create, Terraform will propose to create them on the next apply.
5. Run `terraform apply` to reconcile everything. Terraform will create any missing resources and skip the ones that already exist in state.

The key point is: never manually edit the state file. Use `force-unlock`, `import`, and `apply` to let Terraform sort out the mess.

## Question 4: What Three Provisioned VMs Cannot Do

At the end of Wednesday, we have three Ubuntu VMs running in AWS with nothing on them. No nginx, no Node.js, no service accounts, no systemd units, no application code, no log rotation. The security group controls network access at the cloud level, but there are no firewall rules inside the VMs themselves.

Terraform cannot configure any of these things because of an architectural boundary. Terraform talks to cloud provider APIs (the AWS API, in our case). It can create, update, and destroy resources that the API manages: instances, security groups, subnets, S3 buckets, and so on. But once an EC2 instance is running, Terraform has no mechanism to SSH into it and run commands. The internal state of a VM (installed packages, file permissions, running processes) is not something the AWS API exposes or manages. Terraform's model is "declare a resource, call the API, record the result." It does not have an agent running inside the VM to enforce configuration.

To install nginx using only Terraform, you would use either `user_data` or a `provisioner "remote-exec"` block. With `user_data`, you pass a shell script that runs once when the instance first boots:

```hcl
resource "aws_instance" "kk_api" {
  ami           = data.aws_ami.ubuntu24.id
  instance_type = var.instance_type
  user_data     = <<-EOF
    #!/bin/bash
    apt-get update
    apt-get install -y nginx
  EOF
}
```

The tradeoffs of this approach versus Ansible:

- `user_data` only runs once at instance creation. If nginx gets uninstalled or misconfigured later, Terraform will not detect or fix it. Ansible can be re-run at any time to enforce the desired state.
- If you change the `user_data` script, Terraform will destroy and recreate the entire instance because `user_data` is a create-time-only attribute. Ansible can update the configuration in place without downtime.
- `user_data` has no feedback loop. If the script fails silently, Terraform still marks the instance as created successfully. Ansible reports task-level success or failure, so you know exactly what went wrong.
- Provisioners (`remote-exec`) are officially discouraged by HashiCorp as a last resort. They require SSH access from wherever Terraform runs, they are hard to debug, and they break the declarative model because they are imperative commands hidden inside a declarative config.

Ansible is the right tool for inside-the-VM configuration because it was designed for exactly that job: connecting to running machines and converging them toward a declared state, with idempotent modules, error reporting, and the ability to re-run safely.
