locals {
    current_timestamp  = timestamp()
    current_timestamp_str = formatdate("YYYYMMDDhhmmss", local.current_timestamp)
}

provider "aws" {
  region  = "${var.aws_region}"
}

data "aws_availability_zone" "ami_builder_az" {
  name = "${var.aws_az}"
}


resource "aws_s3_bucket" "isobucket" {
  bucket = "${var.s3_iso_bucket}-${local.current_timestamp_str}"
  acl    = "private"
  acceleration_status = "Enabled"

  tags = {
    Name        = "XRv9k ISO bucket"
    Environment = "ami build bucket"
  }
}

resource "aws_s3_bucket_object" "object" {
  bucket = aws_s3_bucket.isobucket.id
  key    = "xrv9k-fullk9-x.iso"
  source = "/root/iso/${var.xrv9k_iso_name}"
  etag = filemd5("/root/iso/${var.xrv9k_iso_name}")
}


data "aws_ec2_spot_price" "metal" {
  instance_type     = "m5zn.metal"
  availability_zone = "us-west-2a"

  filter {
    name   = "product-description"
    values = ["Linux/UNIX"]
  }
}

resource "aws_default_vpc" "default" {
  tags = {
    Name = "Default VPC"
  }
}

resource "aws_key_pair" "aws_keypair" {
  key_name   = "xrv9k_aws_amibuilder_${local.current_timestamp_str}"
  public_key = "${file(var.ssh_key_public)}"
}

resource "aws_security_group" "server_sg" {
  vpc_id = "${aws_default_vpc.default.id}"

  # SSH ingress access for provisioning
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow SSH access for provisioning"
  }

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["192.168.0.0/16"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_spot_instance_request" "iso2qcow2" {
  ami           = "${var.aws_ami_ubuntu1604[var.aws_region]}"
  spot_price    = "${data.aws_ec2_spot_price.metal.spot_price}"
  instance_type = "${var.ami_builder_instance_type}"
  key_name      = "${aws_key_pair.aws_keypair.key_name}"
  vpc_security_group_ids      = ["${aws_security_group.server_sg.id}"]
  associate_public_ip_address = true
  wait_for_fulfillment = true

  tags = {
    Name = "iso2qcow2_builder"
  }

  depends_on = [
    aws_s3_bucket_object.object,
  ]

  root_block_device  {
      delete_on_termination = true
      volume_size = 60
      volume_type = "gp2"
  }

  provisioner "remote-exec" {
   # Install Python for Ansible
   inline = ["sudo apt-get update && sudo apt-get install -y python3"]

    connection {
      host        = "${self.public_ip}"
      type        = "ssh"
      user        = "ubuntu"
      private_key = "${file(var.ssh_key_private)}"
    }
  }

  provisioner "local-exec" {
    command = "ansible-playbook -u ubuntu -e \"{iso_bucket: '${aws_s3_bucket.isobucket.id}'}\" -e \"{target: '${self.public_ip}'}\" -i '${self.public_ip},' --private-key ${var.ssh_key_private} -T 300 ansible/build_ova.yml"
  }
}
