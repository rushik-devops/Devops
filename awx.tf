# Copyright (c) HashiCorp, Inc.
# SPDX-License-Identifier: MPL-2.0

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.52.0"
    }
  }
  required_version = ">= 1.1.0"
}

provider "aws" {
  region = "us-east-1"
}


data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}


resource "tls_private_key" "awxkey" {
	algorithm = "RSA"
}
resource "local_file" "awx" {
	content = tls_private_key.awxkey.private_key_pem
	filename = "awx.pem"
}
resource "aws_key_pair" "awxhost" {
	key_name = "awx"
	public_key = tls_private_key.awxkey.public_key_openssh
}


locals {
	common_tags = {
		Name = "awx"
	}
}


resource "aws_vpc" "awx" {
  cidr_block = "10.0.0.0/16"
  tags       = local.common_tags
}


resource "aws_subnet" "awx-subnet" {
   vpc_id     = aws_vpc.awx.id
   cidr_block = "10.0.0.0/16"
   tags       = local.common_tags
}


resource "aws_internet_gateway" "awx" {
   vpc_id     = aws_vpc.awx.id
   tags       = local.common_tags
}


resource "aws_route_table" "awx" {
   vpc_id     = aws_vpc.awx.id
   route {
	cidr_block = "0.0.0.0/0"
	gateway_id = aws_internet_gateway.awx.id
   }
   tags       = local.common_tags
}


resource "aws_security_group" "awx-sg" {
  name       = "awx-sg"
  vpc_id     = aws_vpc.awx.id
  depends_on = [aws_vpc.awx]
  ingress {
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
   }

  // connectivity to ubuntu mirrors is required to run `apt-get update` and `apt-get install apache2`
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = local.common_tags
}


resource "aws_route_table_association" "awx" {
	subnet_id	= aws_subnet.awx-subnet.id
	route_table_id	= aws_route_table.awx.id
}


resource "aws_instance" "awx" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.awxhost.key_name
  subnet_id                   = aws_subnet.awx-subnet.id
  vpc_security_group_ids      = [aws_security_group.awx-sg.id]
  associate_public_ip_address = "true"
  tags                        = local.common_tags
}


output "awx_website" {
	value = aws_instance.awx.public_ip
}
