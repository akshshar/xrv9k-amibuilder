variable "xr_version" {
  default = "662"
}

variable "xrv9k_iso_name" {
  default = "xrv9k-fullk9-x.vrr-6.6.2.iso"
}

variable "ssh_key_public" {
  default     = "./ssh/id_rsa.pub"
  description = "Path to the SSH public key for accessing cloud instances. Used for creating AWS keypair."
}

variable "ssh_key_private" {
  default     = "./ssh/id_rsa"
  description = "Path to the SSH public key for accessing cloud instances. Used for creating AWS keypair."
}

variable "aws_region" {
  default = "us-west-2"
}

variable "aws_az" {
  default = "us-west-2a"
}

variable "ami_builder_instance_type" {
  default = "m5zn.metal"
}

variable "ami_snapshot_instance_type" {
  default = "m4.large"
}

variable "aws_ami_ubuntu1604" {
  type = map(string)

  default = {
    "us-west-2"      = "ami-c62eaabe"
  }
}

variable "s3_iso_bucket" {
    default = "xrv9k-iso-bucket"
}
