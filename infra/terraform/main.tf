terraform {
    required_providers {
        aws = {
            source = "hashicorp/aws"
            version = "~> 5.92"
        }
    }

    required_version = ">= 1.2"
}

provider "aws" {
    region = "us-east-2"
    access_key = ""
    secret_key = ""
}

resource "aws_vpc" "vpc-pca" {
    cidr_block = "10.0.0.0/16"
}

resource "aws_internet_gateway" "ig-pca" {
    region = "us-east-2"
}

resource "aws_nat_gateway" "nat-gw" {
    vpc_id = aws_vpc.vpc-pca.id
    subnet_id = aws_subnet.sub-pub-pca.id
    availability_zone_address {
      availability_zone = "us-east-2a"
    }
}

resource "aws_subnet" "sub-pub-pca" {
    vpc_id = aws_vpc.vpc-pca.id
    cidr_block = "10.0.10.0/24"
    availability_zone = "us-east-2a"
    map_public_ip_on_launch = true

    tags = {
        Public = "true"
    }
}

resource "aws_subnet" "sub-priv-pca" {
    vpc_id = aws_vpc.vpc-pca.id
    cidr_block = "10.0.20.0/24"
    availability_zone = "us-east-2a"
    map_public_ip_on_launch = false

    tags = {
      Public = "false"
    }
}


resource "aws_route_table" "private" {
    vpc_id = aws_vpc.vpc-pca.id

    route = {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_nat_gateway.nat-gw.id
    }

    tags = {
        Name = "private"
    }
}

resource "aws_route_table" "public" {
    vpc_id = aws_vpc.vpc-pca.id

    route = {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.ig-pca.id
    }

    tags = {
        Name = "public"
    }
}

resource "aws_route_table_association" "private" {
    subnet_id = aws_subnet.sub-priv-pca.id
    route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "public" {
    subnet_id = aws_subnet.sub-pub-pca.id
    route_table_id = aws_route_table.public.id
}


# -- instâncias --

resource "aws_instance" "bastion-host-ec2" {
    ami = "ami-02ad619be5bc165df" # ubuntu 24.04 lts
    instance_type = "t4g.nano"
    subnet_id = aws_subnet.sub-pub-pca.id

    tags = {
        Name = "bastionhost"
    }

    # adicionar acesso ssh
}

resource "aws_instance" "app-pca-ec2" {
    ami = "ami-02ad619be5bc165df"
    instance_type = "t3.medium"
    subnet_id = aws_subnet.sub-priv-pca.id

    tags = {
        Name = "apppca"
    }
}

# ECS
resource "aws_ecs_task_definition" "front-pca" {
  family = "service"
  container_definitions = jsonencode([
    {
        name = "front-pca"
        image = "" # verificar a imagem no ECR
        cpu = 2
        memory = 20
        essential = true
        portMappings = [
            {
                containerPort = 80
                hostPort = 80
            }
        ]
    }
  ])
}