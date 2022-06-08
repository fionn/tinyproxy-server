locals {
  name = "tinyproxy"

  template_map = {
    proxy_domain_filters = var.proxy_domain_filters
    proxy_clients_acl    = var.proxy_clients_acl
    proxy_listen_port    = var.proxy_listen_port
  }
}

resource "aws_vpc" "tinyproxy" {
  cidr_block                       = "10.0.0.0/24"
  enable_dns_hostnames             = true
  assign_generated_ipv6_cidr_block = true
}

resource "aws_subnet" "tinyproxy" {
  vpc_id     = aws_vpc.tinyproxy.id
  cidr_block = aws_vpc.tinyproxy.cidr_block
}

resource "aws_internet_gateway" "tinyproxy" {
  vpc_id = aws_vpc.tinyproxy.id
}

resource "aws_route_table" "internet" {
  vpc_id = aws_vpc.tinyproxy.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.tinyproxy.id
  }
}

resource "aws_route_table_association" "tinyproxy" {
  subnet_id      = aws_subnet.tinyproxy.id
  route_table_id = aws_route_table.internet.id
}

resource "aws_security_group" "tinyproxy" {
  name   = local.name
  vpc_id = aws_vpc.tinyproxy.id

  ingress {
    description      = "Allow pings"
    from_port        = 8 # ICMP type number
    to_port          = 0 # ICMP code
    protocol         = "icmp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Allow inbound SSH connections"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "Allow all outbound traffic"
    from_port        = 0
    to_port          = 0
    protocol         = -1
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description      = "Allow inbound proxy traffic"
    from_port        = var.proxy_listen_port
    to_port          = var.proxy_listen_port
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    description      = "Proxied outbound traffic"
    from_port        = 443
    to_port          = 443
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  lifecycle {
    # We reference the security group in the instance block
    create_before_destroy = true
  }

  timeouts {
    create = "3m"
    delete = "3m"
  }
}

data "aws_ami" "ubuntu" {
  owners      = ["099720109477"] # Canonical
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-*"]
  }

  filter {
    name   = "root-device-type"
    values = ["ebs"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_eip" "tinyproxy" {
  instance = aws_instance.tinyproxy.id
}

data "cloudinit_config" "tinyproxy" {
  gzip          = false
  base64_encode = false

  part {
    content_type = "text/cloud-config"
    content      = templatefile("${path.root}/data/init.yaml", local.template_map)
  }
}

resource "aws_instance" "tinyproxy" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t2.nano"
  user_data              = data.cloudinit_config.tinyproxy.rendered
  vpc_security_group_ids = [aws_security_group.tinyproxy.id]
  subnet_id              = aws_subnet.tinyproxy.id
  key_name               = aws_key_pair.tinyproxy.key_name

  root_block_device {
    encrypted = true
  }
}

resource "random_id" "key_name" {
  byte_length = 8
  prefix      = "ff-local-key-"
}

resource "aws_key_pair" "tinyproxy" {
  key_name   = random_id.key_name.hex
  public_key = file("~/.ssh/id_ed25519.pub")
}

output "tinyproxy_eip_address" {
  description = "Elastic IP and hostname"
  value = {
    "public_ip"  = aws_eip.tinyproxy.public_ip
    "public_dns" = aws_eip.tinyproxy.public_dns
  }
}
