output "instance_public_ips" {
  description = "The public IP addresses of all servers"
  value       = { for name, server in module.api_servers : name => server.public_ip }
}

output "ssh_commands" {
  description = "SSH commands to connect to each server"
  value       = { for name, server in module.api_servers : name => "ssh ubuntu@${server.public_ip}" }
}
