# Choose the AWS region that will contain the GPU instance.
variable "aws_region" {
  # Store the region as text such as us-east-1.
  type = string
  # Match the region used by the current EC2 instance.
  default = "us-east-1"
}

# Choose an availability zone that currently offers g7e.12xlarge capacity.
variable "availability_zone" {
  # Store the availability-zone name as text.
  type = string
  # Use one of the two zones where AWS offers this instance type.
  default = "us-east-1b"
}

# Choose the EC2 instance type that provides the two GPUs.
variable "instance_type" {
  # Store the instance type as text.
  type = string
  # Use the two-GPU G7e size already selected for this experiment.
  default = "g7e.12xlarge"
}

# Name the public key pair that AWS already stores in the account.
variable "key_pair_name" {
  # Store the AWS key-pair name as text.
  type = string
  # Match the key pair created in the AWS console.
  default = "aws-key-pair"
}

# Restrict incoming SSH traffic to the user's current public IP address.
variable "ssh_cidr" {
  # Store the allowed network in CIDR notation.
  type = string
  # Explain the expected value when Terraform asks for it.
  description = "Your public IPv4 address followed by /32, for example 203.0.113.10/32."

  # Reject a broad network because SSH should not be open to the entire internet.
  validation {
    # Accept a single valid IPv4 address with the /32 suffix.
    condition = can(cidrhost(var.ssh_cidr, 0)) && endswith(var.ssh_cidr, "/32")
    # Show a concrete correction when validation fails.
    error_message = "ssh_cidr must be one IPv4 address ending in /32."
  }
}

# Choose the size of the persistent root EBS disk.
variable "root_volume_size_gib" {
  # Store the disk size as a whole number.
  type = number
  # Allocate enough persistent space for environments and experiment results.
  default = 300
}
