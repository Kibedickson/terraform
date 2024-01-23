provider "aws" {
  region = "eu-west-1"
}
variable "project_name" {
  default = "Terraform Practice"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] # Canonical
}

# # 1. Create vpc
resource "aws_vpc" "vpc" {
  cidr_block = "10.0.0.0/16"
  tags       = {
    Project = var.project_name
  }
}

# # 2. Create Internet Gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id

  tags = {
    Project = var.project_name
  }
}

# # 3. Create Custom Route Table
resource "aws_route_table" "route_table" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = {
    Project = var.project_name
  }
}

# # 4. Create a Subnet
resource "aws_subnet" "subnet-1" {
  vpc_id            = aws_vpc.vpc.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "eu-west-1a"

  tags = {
    Project = var.project_name
  }
}

# # 5. Associate subnet with Route Table
resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.subnet-1.id
  route_table_id = aws_route_table.route_table.id
}

# # 6. Create Security Group to allow port 22,80
resource "aws_security_group" "allow_web" {
  name        = "allow_web"
  description = "Allow Web inbound traffic (22,80) and all outbound traffic"
  vpc_id      = aws_vpc.vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
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
    Project = var.project_name
  }
}
# # 7. Create a network interface with an ip in the subnet that was created in step 4
resource "aws_network_interface" "nc" {
  subnet_id       = aws_subnet.subnet-1.id
  private_ips     = ["10.0.1.50"]
  security_groups = [aws_security_group.allow_web.id]

  tags = {
    Project = var.project_name
  }
}

# # 8. Assign an elastic IP to the network interface created in step 7
resource "aws_eip" "eip" {
  domain                    = "vpc"
  network_interface         = aws_network_interface.nc.id
  associate_with_private_ip = "10.0.1.50"
  depends_on                = [aws_internet_gateway.igw, aws_instance.web]

  tags = {
    Project = var.project_name
  }
}

# # 9. Create Ubuntu server and install/enable nginx
resource "aws_instance" "web" {
  ami               = data.aws_ami.ubuntu.id
  instance_type     = "t2.micro"
  availability_zone = "eu-west-1a"

  network_interface {
    device_index         = 0
    network_interface_id = aws_network_interface.nc.id
  }

  user_data = <<-EOF
      #!/bin/bash
    sudo apt update -y
    sudo apt install nginx -y
    sudo systemctl start nginx
    sudo systemctl enable nginx
    sudo bash -c 'echo terraform tutorial > /var/www/html/index.html'
  EOF

  tags = {
    Project = var.project_name
  }
}

output "server_public_ip" {
  value = aws_eip.eip.public_ip
}

output "server_id" {
  value = aws_instance.web.id
}