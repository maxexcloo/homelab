variable "dns_defaults" {
  description = "Default values for DNS"
  type        = any

  default = {
    priority = null
    proxied  = false
    ttl      = 1
    wildcard = false
  }
}

variable "oci_private_key_base64" {
  description = "OCI private key (base64 encoded)"
  sensitive   = true
  type        = string
}

variable "resend_api_key" {
  description = "Resend API key"
  sensitive   = true
  type        = string
}

variable "server_defaults" {
  description = "Default values for servers"
  type        = any

  default = {
    description                         = null
    enable_b2                           = false
    enable_cloudflare_acme_token        = false
    enable_cloudflare_proxy             = false
    enable_cloudflare_zero_trust_tunnel = false
    enable_docker                       = false
    enable_password                     = false
    enable_resend                       = false
    enable_tailscale                    = false
    fqdn                                = null
    id                                  = null
    management_port                     = 443
    name                                = null
    parent                              = null
    password_hash                       = ""
    password_sensitive                  = null
    platform                            = ""
    public_address                      = null
    public_ipv4                         = null
    public_ipv6                         = null
    region                              = ""
    type                                = "server"
    username                            = "root"
    config = {
      incus = {}
      oci = {
        boot_disk_image_id = null
        boot_disk_size     = 128
        cpus               = 4
        ingress_ports      = [22, 80, 443]
        memory             = 8
        shape              = "VM.Standard.A1.Flex"
      }
    }
  }
}

variable "servers_folder" {
  default     = "Servers"
  description = "Server folder name in Bitwarden"
  type        = string
}

variable "service_defaults" {
  description = "Default values for services"
  type        = any

  default = {
    deploy_to          = []
    description        = null
    enable_b2          = false
    enable_password    = false
    enable_resend      = false
    enable_tailscale   = false
    icon               = null
    id                 = null
    name               = null
    password_sensitive = null
    port               = null
    secrets            = []
    service            = null
    url                = null
  }
}

variable "services_folder" {
  default     = "Services"
  description = "Server folder name in Bitwarden"
  type        = string
}

variable "url_field_pattern" {
  default     = "(^fqdn_|^url_|_(ipv[46]|address)$)"
  description = "Regex pattern to identify fields that should be treated as URLs"
  type        = string
}

variable "oci_compartment_id" {
  default     = ""
  description = "OCI compartment OCID (defaults to tenancy OCID)"
  type        = string
}
