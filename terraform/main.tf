terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Latest Ubuntu 22.04 LTS AMI (Canonical)
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_instance" "devenv" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = var.key_name
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.devenv.id]

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
  }

  dynamic "instance_market_options" {
    for_each = var.use_spot ? [1] : []
    content {
      market_type = "spot"
      spot_options {
        # stop (not terminate) on interruption — EBS data is safe
        instance_interruption_behavior = "stop"
        # persistent request auto-restarts the instance when capacity returns
        spot_instance_type = "persistent"
        # no max_price = bid up to on-demand price, always get spot discount
      }
    }
  }

  tags = {
    Name        = "cloudforge-devenv"
    SpotEnabled = var.use_spot ? "true" : "false"
  }
}

# Persistent EBS data volume — survives stop/start and instance replacement
resource "aws_ebs_volume" "data" {
  availability_zone = aws_instance.devenv.availability_zone
  size              = var.data_volume_size
  type              = "gp3"

  tags = {
    Name = "cloudforge-data"
  }
}

resource "aws_volume_attachment" "data" {
  device_name  = "/dev/xvdf"
  volume_id    = aws_ebs_volume.data.id
  instance_id  = aws_instance.devenv.id
  # Allows Terraform to detach the volume cleanly on destroy
  force_detach = true
}
