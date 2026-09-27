# Print the public IP address after Terraform creates the instance.
output "public_ip" {
  # Read the address assigned by AWS to the new EC2 instance.
  value = aws_instance.gpu.public_ip
}

# Print the public DNS hostname after Terraform creates the instance.
output "public_dns" {
  # Read the hostname assigned by AWS to the new EC2 instance.
  value = aws_instance.gpu.public_dns
}

# Print a ready-to-copy SSH command for connecting from this Mac.
output "ssh_command" {
  # Ubuntu DLAMIs use the ubuntu login account and the downloaded private key.
  value = "ssh -i ~/Downloads/aws-key-pair.pem ubuntu@${aws_instance.gpu.public_dns}"
}

# Print the exact AMI ID selected through AWS's public SSM parameter.
output "ami_id" {
  # Expose the resolved ID so experiment records can identify the image precisely.
  value = nonsensitive(data.aws_ssm_parameter.ubuntu_gpu_ami.value)
}
