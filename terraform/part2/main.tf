variable "mongo_uri" {
  description = "MongoDB Connection String"
  type        = string
  sensitive   = true
}

provider "aws" {
  region = "ap-south-1"
}

# ------------------------------------------------------
# 1. NETWORKING (VPC, IGW, Subnet, Route Table)
# ------------------------------------------------------
resource "aws_vpc" "main_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main_vpc.id
}

resource "aws_subnet" "public_subnet" {
  vpc_id                  = aws_vpc.main_vpc.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true 
  availability_zone       = "ap-south-1a"
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# ------------------------------------------------------
# 2. SECURITY GROUPS (The Firewall Rules)
# ------------------------------------------------------
resource "aws_security_group" "frontend_sg" {
  name        = "frontend_sg"
  description = "Allow public access to Frontend and SSH"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 4000
    to_port     = 4000
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

resource "aws_security_group" "backend_sg" {
  name        = "backend_sg"
  description = "Allow traffic ONLY from the Frontend SG"
  vpc_id      = aws_vpc.main_vpc.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Allow SSH for debugging
  }

  ingress {
    from_port       = 5000
    to_port         = 5000
    protocol        = "tcp"
    # CRITICAL: We don't use 0.0.0.0/0 here. We link it to the Frontend SG.
    security_groups = [aws_security_group.frontend_sg.id] 
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ------------------------------------------------------
# 3. EC2 INSTANCES
# ------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

# BUILD BACKEND FIRST
resource "aws_instance" "backend_instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.backend_sg.id]
  key_name               = "aws-assignment-key"

  user_data = templatefile("backend-script.tftpl", {
    mongo_uri_secret = var.mongo_uri
  })

  tags = {
    Name = "backend-instance"
  }
}

# BUILD FRONTEND SECOND
resource "aws_instance" "frontend_instance" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.micro"
  subnet_id              = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.frontend_sg.id]
  key_name               = "aws-assignment-key"

  # We pass the backend's IP directly into the frontend script!
  user_data = templatefile("frontend-script.tftpl", {
    backend_ip = aws_instance.backend_instance.private_ip
    # backend_ip = aws_instance.backend_instance.public_ip
  })

  tags = {
    Name = "frontend-instance"
  }
}

# ------------------------------------------------------
# 4. OUTPUTS
# ------------------------------------------------------
output "frontend_public_ip" {
  value = aws_instance.frontend_instance.public_ip
}

output "backend_public_ip" {
  value = aws_instance.backend_instance.public_ip
}