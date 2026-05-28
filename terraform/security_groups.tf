resource "aws_security_group" "devenv" {
  name        = "cloudforge-${var.env_name}"
  description = "Cloudforge ${var.env_name} - SSH (operator) and web app (users)"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH - operator bootstrap access only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ssh_allowed_cidrs
  }

  ingress {
    description = "Web app - primary end-user access path"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = var.web_allowed_cidrs
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "cloudforge-${var.env_name}"
    Environment = var.env_name
  }
}
