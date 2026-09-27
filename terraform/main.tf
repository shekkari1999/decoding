# Read the latest official x86_64 Ubuntu 24.04 NVIDIA-driver DLAMI ID from AWS.
data "aws_ssm_parameter" "ubuntu_gpu_ami" {
  # AWS maintains this public parameter and updates it when a DLAMI is released.
  name = "/aws/service/deeplearning/ami/x86_64/base-oss-nvidia-driver-gpu-ubuntu-24.04/latest/ami-id"
}

# Find the account's default VPC so this small setup does not create a new network.
data "aws_vpc" "default" {
  # Select only the VPC marked as the default for this region.
  default = true
}

# Find the default subnet in the explicitly selected supported availability zone.
data "aws_subnet" "selected" {
  # Filter subnet results by the selected default VPC ID.
  filter {
    # Use AWS's VPC-ID filter field.
    name = "vpc-id"
    # Match only the default VPC discovered above.
    values = [data.aws_vpc.default.id]
  }

  # Filter subnet results by the supported availability zone.
  filter {
    # Use AWS's availability-zone filter field.
    name = "availability-zone"
    # Match the zone chosen in terraform.tfvars.
    values = [var.availability_zone]
  }

  # Require the subnet AWS marks as the default for this availability zone.
  default_for_az = true
}

# Create a firewall rule set dedicated to SSH access for this GPU instance.
resource "aws_security_group" "gpu_ssh" {
  # Give the security group a readable AWS console name.
  name = "decoding-gpu-ssh"
  # Explain the security group's purpose in AWS.
  description = "Allow SSH to the decoding GPU instance from one public IP"
  # Place the security group inside the default VPC.
  vpc_id = data.aws_vpc.default.id

  # Permit inbound SSH from only the user-supplied address.
  ingress {
    # Describe the inbound rule in the AWS console.
    description = "SSH from the current public IP"
    # Open the standard SSH port at the start of the range.
    from_port = 22
    # Open only the same SSH port at the end of the range.
    to_port = 22
    # SSH uses the TCP transport protocol.
    protocol = "tcp"
    # Limit access to one public IPv4 address.
    cidr_blocks = [var.ssh_cidr]
  }

  # Allow the instance to reach package repositories and model registries.
  egress {
    # Describe the outbound rule in the AWS console.
    description = "Allow all outbound traffic"
    # A value of zero is required when all protocols are allowed.
    from_port = 0
    # A value of zero is required when all protocols are allowed.
    to_port = 0
    # A value of -1 means every network protocol.
    protocol = "-1"
    # Allow outbound connections to any IPv4 destination.
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Add a readable label to the security group.
  tags = {
    # Display this name in the AWS console.
    Name = "decoding-gpu-ssh"
  }
}

# Create the GPU server that Terraform will later be able to destroy cleanly.
resource "aws_instance" "gpu" {
  # Boot from the latest official NVIDIA-driver Ubuntu DLAMI resolved above.
  ami = data.aws_ssm_parameter.ubuntu_gpu_ami.value
  # Allocate the requested two-GPU EC2 size.
  instance_type = var.instance_type
  # Install the public half of the existing AWS key pair for SSH authentication.
  key_name = var.key_pair_name
  # Launch into the default subnet in the explicitly supported availability zone.
  subnet_id = data.aws_subnet.selected.id
  # Assign a public IPv4 address so the local Mac can connect over SSH.
  associate_public_ip_address = true
  # Attach the narrowly scoped SSH security group created above.
  vpc_security_group_ids = [aws_security_group.gpu_ssh.id]

  # Configure the persistent operating-system disk.
  root_block_device {
    # Use general-purpose SSD storage with independent size and performance controls.
    volume_type = "gp3"
    # Allocate the requested persistent disk capacity.
    volume_size = var.root_volume_size_gib
    # Encrypt the EBS volume using the account's default EBS encryption key.
    encrypted = true
    # Remove the disk when Terraform destroys the instance to avoid orphaned charges.
    delete_on_termination = true
  }

  # Add readable labels to the EC2 instance.
  tags = {
    # Display this name in the AWS console.
    Name = "inference-decoding"
    # Record which tool owns the lifecycle of the instance.
    ManagedBy = "Terraform"
  }
}
