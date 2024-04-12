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
  region = "us-east-2"
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


resource "tls_private_key" "jenkinskey" {
	algorithm = "RSA"
}
resource "local_file" "jenkins" {
	content = tls_private_key.jenkinskey.private_key_pem
	filename = "jenkins.pem"
}
resource "aws_key_pair" "jenkinshost" {
	key_name = "jenkins"
	public_key = tls_private_key.jenkinskey.public_key_openssh
}


locals {
	common_tags = {
		Name = "jenkins"
	}
}


resource "aws_vpc" "jenkins" {
  cidr_block = "10.0.0.0/16"
  tags       = local.common_tags
}


resource "aws_subnet" "jenkins-subnet" {
   vpc_id     = aws_vpc.jenkins.id
   cidr_block = "10.0.0.0/16"
   tags       = local.common_tags
}


resource "aws_internet_gateway" "jenkins" {
   vpc_id     = aws_vpc.jenkins.id
   tags       = local.common_tags
}


resource "aws_route_table" "jenkins" {
   vpc_id     = aws_vpc.jenkins.id
   route {
	cidr_block = "0.0.0.0/0"
	gateway_id = aws_internet_gateway.jenkins.id
   }
   tags       = local.common_tags
}


resource "aws_security_group" "jenkins-sg" {
  name       = "jenkins-sg"
  vpc_id     = aws_vpc.jenkins.id
  depends_on = [aws_vpc.jenkins]
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


resource "aws_instance" "jenkins" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = "t2.micro"
  key_name                    = aws_key_pair.jenkinshost.key_name
  subnet_id                   = aws_subnet.jenkins-subnet.id
  vpc_security_group_ids      = [aws_security_group.jenkins-sg.id]
  associate_public_ip_address = "true"
  tags                        = local.common_tags

  user_data = <<-EOF
              #!/bin/bash
	      sudo apt-get install openjdk-8-jdk -y
              sudo apt-get install openjdk-11-jdk-headless -y
              sudo wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
              echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc]" https://pkg.jenkins.io/debian-stable binary/ | sudo tee /etc/apt/sources.list.d/jenkins.list > /dev/null
              sudo apt-get update
              sudo apt-get install jenkins -y
              EOF
}


output "jenkins-address" {
  value = "${aws_instance.jenkins.public-ip}:8080"
}
