# KijaniKiosk API Server - Desired State Specification

## Identity

- Name: kijanikiosk-api-staging
- Environment tag: week4-monday
- Owner tag: erick

## Compute

- Provider: Amazon Web Services (AWS)
- Region: af-south-1 (Africa - Cape Town)
- Instance type: t3.micro
- Operating system: Ubuntu 24.04.4 LTS (Codename: noble)

## Networking

- VPC: vpc-075e27fb21f6549ca (default VPC in af-south-1)
- Subnet: subnet-04977da9e75e06cc9 (public subnet)
- Assign public IP: yes (13.245.4.6)
- Private IP: 172.31.10.109/20

## Access Control

- SSH access: port 22, source [your IP]/32 only
- HTTP access: port 80, source 0.0.0.0/0
- All other inbound: deny
- All outbound: allow
- Security group: launch-wizard-1

## Storage

- Root volume: 8 GB, type gp3

## Authentication

- SSH key pair name: personal laptop

## What must NOT exist on this server after provisioning

- No default password authentication
- No services listening other than sshd
- No world-writable directories outside /tmp

## Open questions (things that will need decisions before Terraform can encode this)

- Security group `launch-wizard-1` was auto-generated at launch; a purpose-named group with explicit ingress rules should replace it before encoding in Terraform
- The default VPC was used for convenience; decide whether a dedicated VPC with a custom IP address range is needed for staging
- SSH source IP is not yet locked to a specific Ip address range; must be narrowed to the team's static IP(s)
- No HTTPS (port 443) rule is defined yet; will the API serve TLS-terminated traffic or sit behind a load balancer?

## Hardest Decision and Why

The toughest call was the security group. When I launched the instance, I just went with the auto-generated `launch-wizard-1` group because it was quick and easy. But that shortcut left me uneasy , the name tells you nothing about what it does, I'm not fully sure which ports it opens, and anyone looking at this setup later would have no idea what access it actually allows. Other decisions like picking the region or instance type were simple: pick the closest region, pick the cheapest instance. But with the security group I was trading convenience now for cleanup work later. It's the one decision I know I'll have to redo properly before this can be turned into Terraform, since everything else , SSH access, HTTP traffic, who can reach the server , depends on getting those firewall rules right.
