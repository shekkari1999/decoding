# GPU instance with Terraform

This folder defines one `g7e.12xlarge` EC2 instance in `us-east-1b` for the decoding experiment. It uses AWS's latest x86_64 Ubuntu 24.04 NVIDIA-driver Deep Learning AMI, a 300 GiB encrypted gp3 root disk, the existing `aws-key-pair`, and an SSH firewall rule limited to one public IP address.

## What Terraform manages

`terraform apply` creates the EC2 instance and its SSH security group. `terraform destroy` deletes both resources and the 300 GiB root volume. The 1.7 TiB NVMe instance-store disk is part of the G7e host; it is temporary and is not an EBS resource managed by this configuration.

## First-time setup

```bash
# Enter the folder containing the Terraform configuration.
cd terraform
# Copy the safe example so local values stay outside Git.
cp terraform.tfvars.example terraform.tfvars
# Edit ssh_cidr in terraform.tfvars to your current public IPv4 address plus /32.
# Configure AWS credentials locally; Terraform never receives the private SSH key.
aws configure
# Download the AWS provider declared in versions.tf.
terraform init
# Check syntax and internal consistency before contacting EC2.
terraform validate
# Preview the resources and estimated changes without creating anything.
terraform plan -out=gpu.tfplan
# Create exactly the reviewed plan.
terraform apply gpu.tfplan
# Print the ready-to-copy SSH command after creation.
terraform output -raw ssh_command
```

## Connect

```bash
# Evaluate the Terraform output and connect with the local private key.
$(terraform output -raw ssh_command)
```

## Delete the instance

```bash
# Preview the deletion before changing AWS resources.
terraform plan -destroy
# Delete the Terraform-managed instance, root disk, and security group.
terraform destroy
```

Terraform can destroy only resources recorded in its state. The manually launched EC2 instance is not in this state and must be terminated separately in the AWS console.
