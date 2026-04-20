output "instance_public_ips" {
  description = "The public IP addresses of all servers"
  value       = { for name, server in module.api_servers : name => server.public_ip }
}

output "ssh_commands" {
  description = "SSH commands to connect to each server"
  value       = { for name, server in module.api_servers : name => "ssh ubuntu@${server.public_ip}" }
}

output "ansible_inventory" {
  description = "Ansible inventory in INI format"
  value       = <<-EOT
[api]
api-staging ansible_host=${module.api_servers["api"].public_ip}

[payments]
payments-staging ansible_host=${module.api_servers["payments"].public_ip}

[logs]
logs-staging ansible_host=${module.api_servers["logs"].public_ip}

[kijanikiosk:children]
api
payments
logs

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/id_ed25519
EOT
}
