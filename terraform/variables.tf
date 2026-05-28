variable "region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "instance_type" {
  description = "EC2 instance type (must support NVIDIA GPU)"
  type        = string
  default     = "g4dn.xlarge"
}

variable "key_name" {
  description = "Name of the EC2 key pair to use for SSH access"
  type        = string
}

variable "data_volume_size" {
  description = "Size of the persistent EBS data volume in GB"
  type        = number
  default     = 200
}

variable "allowed_cidr" {
  description = "CIDR block allowed SSH and web-app access. Restrict to your IP for better security."
  type        = string
  default     = "0.0.0.0/0"
}

variable "use_spot" {
  description = "Use a spot instance for ~70% cost savings. Safe to use — EBS data survives interruption."
  type        = bool
  default     = true
}
