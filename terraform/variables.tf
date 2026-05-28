variable "env_name" {
  description = "Human-readable environment name slug (e.g. 'default', 'alice'). Used in resource names and tags."
  type        = string
  default     = "default"
}

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

variable "ssh_allowed_cidrs" {
  description = "CIDR blocks allowed SSH (port 22) access. Restrict to known operator IPs — never 0.0.0.0/0."
  type        = list(string)
}

variable "web_allowed_cidrs" {
  description = "CIDR blocks allowed web app (port 8080) access. Can be broader than SSH."
  type        = list(string)
}

variable "use_spot" {
  description = "Use a spot instance for ~70% cost savings. Safe to use — EBS data survives interruption."
  type        = bool
  default     = true
}
