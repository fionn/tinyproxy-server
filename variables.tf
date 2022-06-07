variable "aws_region" {
  type    = string
  default = "ap-northeast-1"
}

variable "proxy_domain_filters" {
  description = "Allow connections to these domains"
  type        = list(string)
  default     = ["example.com"]
}

variable "proxy_clients_acl" {
  description = "Client subnets we allow connections from"
  type        = list(string)
  default     = ["0.0.0.0/0", "::/0"]
}

variable "proxy_listen_port" {
  description = "Port to listen on"
  type        = number
  default     = 8888
}
