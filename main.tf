# 1. VPC
resource "aws_vpc" "bayer_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "bayer-vpc"
  }
}

# 2. Internet Gateway
resource "aws_internet_gateway" "bayer_igw" {
  vpc_id = aws_vpc.bayer_vpc.id

  tags = {
    Name = "bayer-igw"
  }
}

# 3. Public Subnet 1
resource "aws_subnet" "bayer_public_subnet_1" {
  vpc_id                  = aws_vpc.bayer_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "bayer-public-subnet-1"
  }
}

# 5. Public Route Table
resource "aws_route_table" "bayer_public_rt" {
  vpc_id = aws_vpc.bayer_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.bayer_igw.id
  }

  tags = {
    Name = "bayer-public-route-table"
  }
}

# 6. Associate Subnet 1 with Route Table
resource "aws_route_table_association" "bayer_assoc_subnet_1" {
  subnet_id      = aws_subnet.bayer_public_subnet_1.id
  route_table_id = aws_route_table.bayer_public_rt.id
}


# 8. Creating Elastic IP for NAT Gateway
resource "aws_eip" "nat_1" {
  domain = "vpc"
  tags = {
    Name = "nat_eip"
  }
}

# Creating NAT Gateway in public subnet 1
resource "aws_nat_gateway" "nat_1" {
  allocation_id = aws_eip.nat_1.id
  subnet_id     = aws_subnet.bayer_public_subnet_1.id
  tags = {
  Name = "bayer_natgateway_for_pri_subs"
  }
}

#  Creating Private Subnet 1
resource "aws_subnet" "bayer_private_subnet_1" {
  vpc_id                  = aws_vpc.bayer_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-south-1a"
  map_public_ip_on_launch = false

  tags = {
    Name = "bayer_private_subnet_1"
  }
}

# Creating Private Subnet 2
resource "aws_subnet" "bayer_private_subnet_2" {
  vpc_id                  = aws_vpc.bayer_vpc.id
  cidr_block              = "10.0.3.0/24"
  availability_zone       = "ap-south-1b"
  map_public_ip_on_launch = false

  tags = {
    Name = "bayer_private_subnet_2"
  }
}

#  Private Route Table
resource "aws_route_table" "bayer_private_rt" {
  vpc_id = aws_vpc.bayer_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_1.id
  }

  tags = {
    Name = "bayer_public_route_table"
  }
}

#  Associate Private Subnet 1 with Route Table
resource "aws_route_table_association" "assoc_pri_subnet_1" {
  subnet_id      = aws_subnet.bayer_private_subnet_1.id
  route_table_id = aws_route_table.bayer_private_rt.id
}

#  Associate Subnet 2 with Route Table
resource "aws_route_table_association" "assoc_pri_subnet_2" {
  subnet_id      = aws_subnet.bayer_private_subnet_2.id
  route_table_id = aws_route_table.bayer_private_rt.id
}

#  Creating security group for Application Instance
resource "aws_security_group" "bayer_app_sg" {
  name        = "bayer-app-sg"
  description = "Allow HTTP & SSH"
  vpc_id      = aws_vpc.bayer_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 22
    to_port     = 22
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

# Creating security group for Application Instances
resource "aws_security_group" "bayer_db_sg" {
  name   = "bayer-db-sg"
  vpc_id = aws_vpc.bayer_vpc.id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.bayer_app_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Creating IAM role for ec2 instance for secrets manager
resource "aws_iam_role" "ec2_app_role" {
  name = "app_secrets_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "app_secrets_policy" {
  name = "app_secrets_policy"
  role = aws_iam_role.ec2_app_role.id
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Action = ["secretsmanager:GetSecretValue"],
      Resource = "*"
    }]
  })
}

resource "aws_iam_instance_profile" "app_instance_profile" {
  name = "app_instance_profile"
  role = aws_iam_role.ec2_app_role.name
}

# Creating Application Instance
resource "aws_instance" "app_ec2" {
  ami                         = "ami-0b09627181c8d5778"
  instance_type               = "t2.micro"
  subnet_id                   = aws_subnet.bayer_public_subnet_1.id
  vpc_security_group_ids      = [aws_security_group.bayer_app_sg.id]
  iam_instance_profile        = aws_iam_instance_profile.app_instance_profile.name
  associate_public_ip_address = true

  tags = {
    Name = "bayer-application"
  }
}

# Creating db subnet groups Aurora cluster, aurora instance
resource "aws_db_subnet_group" "subnet_group" {
  name       = "aurora-subnet-group"

  subnet_ids = [
    aws_subnet.bayer_private_subnet_1.id,
    aws_subnet.bayer_private_subnet_2.id
  ]
}

resource "aws_rds_cluster" "db_cluster" {
  cluster_identifier           = "bayer-mysql-cluster"
  engine                       = "aurora-mysql"
  engine_version               = "8.0.mysql_aurora.3.04.0"
  database_name                = "bayer_aurora_db"
  db_subnet_group_name         = aws_db_subnet_group.subnet_group.name
  vpc_security_group_ids       = [aws_security_group.bayer_db_sg.id]
  manage_master_user_password  = true
  master_username              = "admin"
  skip_final_snapshot          = true
}

resource "aws_rds_cluster_instance" "aurora_db_instance" {
  identifier              = "bayer-aurora-instance"
  cluster_identifier      = aws_rds_cluster.db_cluster.id
  instance_class          = "db.t3.medium"
  engine                  = aws_rds_cluster.db_cluster.engine
  db_subnet_group_name    = aws_db_subnet_group.subnet_group.name
}

output "db_endpoint" {
  value = aws_rds_cluster.db_cluster.endpoint
}
