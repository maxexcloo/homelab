variable "default_email" {
  description = "Default email for notifications and accounts"
  type        = string
}

variable "default_organization" {
  description = "Default organization name"
  type        = string
}

variable "default_platform_resources" {
  description = "Default resources to create for each platform type"
  type        = map(list(string))

  default = {
    router = ["desec", "tailscale"]
    server = ["b2", "cloudflare", "desec", "resend", "tailscale"]
    vm     = ["b2", "cloudflare", "desec", "resend", "tailscale"]
  }
}

variable "dns" {
  default     = {}
  description = "DNS records by zone"

  type = map(list(object({
    content  = string
    name     = string
    priority = optional(number)
    proxied  = optional(bool, false)
    type     = string
    wildcard = optional(bool, false)
  })))
}

variable "domain_acme" {
  description = "Subdomain to use for ACME challenge validation, must be in a Cloudflare managed zone"
  type        = string
}

variable "domain_external" {
  description = "External domain for public services"
  type        = string
}

variable "domain_internal" {
  description = "Internal domain for private services"
  type        = string
}

variable "onepassword_homelab_field_schema" {
  description = "Field schema for homelab 1Password items"

  default = {
    input = {
      description     = "STRING"
      flags           = "STRING"
      management_port = "STRING"
      parent          = "STRING"
      paths           = "STRING"
      private_ipv4    = "URL"
      public_address  = "URL"
      public_ipv4     = "URL"
      public_ipv6     = "URL"
    }
    output = {
      b2_application_key       = "CONCEALED"
      b2_application_key_id    = "STRING"
      b2_bucket_name           = "STRING"
      b2_endpoint              = "URL"
      cloudflare_account_token = "CONCEALED"
      cloudflare_tunnel_token  = "CONCEALED"
      desec_token              = "CONCEALED"
      fqdn_external            = "URL"
      fqdn_internal            = "URL"
      public_address           = "URL"
      region                   = "STRING"
      resend_api_key           = "CONCEALED"
      tailscale_auth_key       = "CONCEALED"
      tailscale_ipv4           = "URL"
      tailscale_ipv6           = "URL"
    }
  }

  type = object({
    input  = map(string)
    output = map(string)
  })
}

variable "onepassword_homelab_vault" {
  default     = "Homelab"
  description = "1Password homelab vault"
  type        = string
}

variable "onepassword_services_field_schema" {
  description = "Field schema for services 1Password items"

  default = {
    input = {
      api_key           = "CONCEALED"
      database_password = "CONCEALED"
      deploy_to         = "STRING"
      description       = "STRING"
      dns               = "STRING"
      enable_b2         = "STRING"
      enable_monitoring = "STRING"
      enable_resend     = "STRING"
      flags             = "STRING"
      icon              = "STRING"
      port              = "STRING"
      secret_hash       = "CONCEALED"
      service           = "STRING"
      url               = "URL"
    }
    output = {
      b2_application_key    = "CONCEALED"
      b2_application_key_id = "STRING"
      b2_bucket_name        = "STRING"
      b2_endpoint           = "URL"
      fqdn_external         = "URL"
      fqdn_internal         = "URL"
      platform              = "STRING"
      resend_api_key        = "CONCEALED"
    }
  }

  type = object({
    input  = map(string)
    output = map(string)
  })
}

variable "onepassword_services_vault" {
  default     = "Services"
  description = "1Password services vault"
  type        = string
}

variable "resources" {
  default     = ["b2", "cloudflare", "resend", "tailscale"]
  description = "List of all available resources that can be enabled via flags"
  type        = list(string)
}
