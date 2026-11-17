terraform {
  required_version = ">= 1.5.7, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "hosted_zone_id" {
  description = "Public Route 53 hosted zone ID for dialloholmes.net"
  type        = string
}

provider "aws" {
  region  = var.aws_region
  profile = "freakyjensen"

  default_tags {
    tags = {
      Project   = "US-West-Linux-ALB"
      ManagedBy = "Terraform"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ssm_parameter" "amazon_linux" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  servers = {
    Linux1 = 0
    Linux2 = 1
  }
}

# Create the network.
resource "aws_vpc" "lab" {
  cidr_block           = "10.42.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "us-west-linux-vpc"
  }
}

resource "aws_internet_gateway" "lab" {
  vpc_id = aws_vpc.lab.id
}

# Create two subnets in separate Availability Zones.
resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.lab.id
  cidr_block              = cidrsubnet(aws_vpc.lab.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "us-west-linux-public-${count.index + 1}"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.lab.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.lab.id
  }
}

resource "aws_route_table_association" "public" {
  count = 2

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Allow public HTTP access to the load balancer.
resource "aws_security_group" "alb" {
  name_prefix = "linux-alb-"
  description = "Public HTTP access to the ALB"
  vpc_id      = aws_vpc.lab.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "linux-alb-security-group"
  }
}

# Allow HTTP to the servers only from the load balancer.
resource "aws_security_group" "web" {
  name_prefix = "linux-web-"
  description = "HTTP from the ALB only"
  vpc_id      = aws_vpc.lab.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "linux-web-security-group"
  }
}

# Create Linux1 and Linux2 and install Apache automatically.
resource "aws_instance" "web" {
  for_each = local.servers

  ami                         = data.aws_ssm_parameter.amazon_linux.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.public[each.value].id
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true
  user_data_replace_on_change = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_size = 8
    volume_type = "gp3"
    encrypted   = true
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf install -y httpd
    printf '%s\n' 'Welcome to ${each.key} in US West' > /var/www/html/index.html
    systemctl enable --now httpd
  EOF

  tags = {
    Name = each.key
  }

  depends_on = [aws_route_table_association.public]
}

# Create the public Application Load Balancer.
resource "aws_lb" "web" {
  name_prefix        = "dlc-"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = aws_subnet.public[*].id

  tags = {
    Name = "us-west-linux-alb"
  }

  depends_on = [aws_route_table_association.public]
}

# Configure the backend target group and health checks.
resource "aws_lb_target_group" "web" {
  name_prefix = "dlc-"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.lab.id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }
}

# Register both servers as load balancer targets.
resource "aws_lb_target_group_attachment" "web" {
  for_each = aws_instance.web

  target_group_arn = aws_lb_target_group.web.arn
  target_id        = each.value.id
  port             = 80
}

# Forward incoming HTTP requests to the servers.
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.web.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web.arn
  }
}

# Point the hostname to the ALB using an A alias record.
resource "aws_route53_record" "web" {
  zone_id = var.hosted_zone_id
  name    = "dlc-linux-lb.dialloholmes.net"
  type    = "A"

  alias {
    name                   = aws_lb.web.dns_name
    zone_id                = aws_lb.web.zone_id
    evaluate_target_health = true
  }
}

output "website_url" {
  value = "http://${aws_route53_record.web.fqdn}"
}

output "alb_url" {
  value = "http://${aws_lb.web.dns_name}"
}

output "linux1_id" {
  value = aws_instance.web["Linux1"].id
}

output "linux2_id" {
  value = aws_instance.web["Linux2"].id
}

output "target_group_arn" {
  value = aws_lb_target_group.web.arn
}

output "aws_region" {
  value = var.aws_region
}
