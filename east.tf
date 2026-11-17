# East Coast provider. Existing resources keep using the West provider.
provider "aws" {
  alias   = "east"
  region  = "us-east-1"
  profile = "freakyjensen"

  default_tags {
    tags = {
      Project   = "US-East-West-Linux-ALB"
      ManagedBy = "Terraform"
    }
  }
}

data "aws_availability_zones" "east" {
  provider = aws.east
  state    = "available"
}

data "aws_ssm_parameter" "east_linux" {
  provider = aws.east
  name     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

locals {
  east_servers = {
    Linux3 = 0
    Linux4 = 1
  }
}

resource "aws_vpc" "east" {
  provider             = aws.east
  cidr_block           = "10.43.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "us-east-linux-vpc"
  }
}

resource "aws_internet_gateway" "east" {
  provider = aws.east
  vpc_id   = aws_vpc.east.id
}

resource "aws_subnet" "east_public" {
  provider = aws.east
  count    = 2

  vpc_id                  = aws_vpc.east.id
  cidr_block              = cidrsubnet(aws_vpc.east.cidr_block, 8, count.index)
  availability_zone       = data.aws_availability_zones.east.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "us-east-linux-public-${count.index + 1}"
  }
}

resource "aws_route_table" "east_public" {
  provider = aws.east
  vpc_id   = aws_vpc.east.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.east.id
  }
}

resource "aws_route_table_association" "east_public" {
  provider = aws.east
  count    = 2

  subnet_id      = aws_subnet.east_public[count.index].id
  route_table_id = aws_route_table.east_public.id
}

resource "aws_security_group" "east_alb" {
  provider    = aws.east
  name_prefix = "east-alb-"
  description = "Public HTTP access to the East ALB"
  vpc_id      = aws_vpc.east.id

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
}

resource "aws_security_group" "east_web" {
  provider    = aws.east
  name_prefix = "east-web-"
  description = "HTTP from the East ALB only"
  vpc_id      = aws_vpc.east.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.east_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "east_web" {
  provider = aws.east
  for_each = local.east_servers

  ami                         = data.aws_ssm_parameter.east_linux.value
  instance_type               = "t3.micro"
  subnet_id                   = aws_subnet.east_public[each.value].id
  vpc_security_group_ids      = [aws_security_group.east_web.id]
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

  user_data = <<-SCRIPT
    #!/bin/bash
    set -euxo pipefail
    dnf install -y httpd
    printf '%s\n' 'Welcome to ${each.key} in US East' > /var/www/html/index.html
    systemctl enable --now httpd
  SCRIPT

  tags = {
    Name = each.key
  }

  depends_on = [aws_route_table_association.east_public]
}

resource "aws_lb" "east" {
  provider           = aws.east
  name_prefix        = "east-"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.east_alb.id]
  subnets            = aws_subnet.east_public[*].id

  tags = {
    Name = "us-east-linux-alb"
  }

  depends_on = [aws_route_table_association.east_public]
}

resource "aws_lb_target_group" "east" {
  provider    = aws.east
  name_prefix = "east-"
  port        = 80
  protocol    = "HTTP"
  target_type = "instance"
  vpc_id      = aws_vpc.east.id

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

resource "aws_lb_target_group_attachment" "east" {
  provider = aws.east
  for_each = aws_instance.east_web

  target_group_arn = aws_lb_target_group.east.arn
  target_id        = each.value.id
  port             = 80
}

resource "aws_lb_listener" "east_http" {
  provider          = aws.east
  load_balancer_arn = aws_lb.east.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.east.arn
  }
}

output "east_alb_url" {
  value = "http://${aws_lb.east.dns_name}"
}

output "linux3_id" {
  value = aws_instance.east_web["Linux3"].id
}

output "linux4_id" {
  value = aws_instance.east_web["Linux4"].id
}

output "east_target_group_arn" {
  value = aws_lb_target_group.east.arn
}
