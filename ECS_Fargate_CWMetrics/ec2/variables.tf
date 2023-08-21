# Variables for the EC2 instance profile

variable "repourl" {
  type = string
}

variable "repoarn" {
  type = string
}

variable "region" {
  type = string
}

variable "vpc" {
  type = string
}

variable "subnetid" {
  type = string
}

variable "accountid" {
  type = string
}

variable "reponame" {
  type = string
}

variable "instancetype" {
  type    = string
  default = "t3a.medium"
}