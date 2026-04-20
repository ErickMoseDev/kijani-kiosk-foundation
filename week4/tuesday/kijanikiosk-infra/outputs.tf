output "instance_public_ip" {
  description = "The public IP address of the kk_api"
  value       = aws_instance.kk_api.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the API server"
  value       = "ssh ubuntu@${aws_instance.kk_api.public_ip}" # I dont have the .pem key name locally
}
