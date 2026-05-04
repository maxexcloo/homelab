variable "account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "ingress" {
  description = "Tunnel ingress rules (list of hostname objects plus a final catch-all)"
  type = list(object({
    hostname = optional(string)
    service  = string
    origin_request = optional(object({
      no_tls_verify      = optional(bool)
      origin_server_name = optional(string)
    }))
  }))
}

variable "name" {
  description = "Server key used for resource naming"
  type        = string
}
