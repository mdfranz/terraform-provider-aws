variable "aws_region" {
  description = "The AWS region to create things in."
  default     = "us-west-2"
}

variable "ssh_keyname" { } 

variable "ami_id" {
  default = "ami-51537029"
}

variable "az_count" {
  description = "Number of AZs to cover in a given AWS region"
  default     = "2"
}

variable "instance_type" {
  default     = "t2.nano"
  description = "AWS instance type"
}

variable "admin_cidr_ingress" {
  description = "CIDR to allow tcp/22 ingress to EC2 instance"
  default     = "0.0.0.0/0"

}
