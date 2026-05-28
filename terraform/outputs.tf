output "instance_id" {
  description = "EC2 instance ID"
  value       = aws_instance.devenv.id
}

output "public_ip" {
  description = "Public IP address of the instance"
  value       = aws_instance.devenv.public_ip
}

output "ssh_command" {
  description = "SSH command to connect to the instance"
  value       = "ssh -i ~/.ssh/${var.key_name}.pem ubuntu@${aws_instance.devenv.public_ip}"
}

output "start_command" {
  description = "AWS CLI command to start the instance"
  value       = "aws ec2 start-instances --instance-ids ${aws_instance.devenv.id} --region ${var.region}"
}

output "stop_command" {
  description = "AWS CLI command to stop the instance"
  value       = "aws ec2 stop-instances --instance-ids ${aws_instance.devenv.id} --region ${var.region}"
}

output "env_name" {
  description = "Environment name slug"
  value       = var.env_name
}
