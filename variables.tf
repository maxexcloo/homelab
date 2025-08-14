variable "default_email" {
  description = "Default email for notifications and accounts"
  type        = string
}

variable "default_organization" {
  description = "Default organization name"
  type        = string
}

variable "default_homelab_resources" {
  description = "Default resources to create for each homelab platform type"
  type        = map(list(string))

  default = {
    router = ["tailscale"]
    server = ["b2", "cloudflare", "resend", "tailscale"]
    vm     = ["b2", "cloudflare", "resend", "tailscale"]
  }
}

variable "default_services_resources" {
  description = "Default resources to create for each services platform type"
  type        = map(list(string))

  default = {
    docker  = []
    truenas = []
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
      management_port = "STRING"
      parent          = "STRING"
      paths           = "STRING"
      private_ipv4    = "URL"
      public_address  = "URL"
      public_ipv4     = "URL"
      public_ipv6     = "URL"
      resources       = "STRING"
      tags            = "STRING"
    }
    output = {
      b2_application_key       = "CONCEALED"
      b2_application_key_id    = "STRING"
      b2_bucket_name           = "STRING"
      b2_endpoint              = "URL"
      cloudflare_account_token = "CONCEALED"
      cloudflare_tunnel_token  = "CONCEALED"
      fqdn_external            = "URL"
      fqdn_internal            = "URL"
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
      icon              = "STRING"
      port              = "STRING"
      secret_hash       = "CONCEALED"
      service           = "STRING"
      resources         = "STRING"
      tags              = "STRING"
    }
    output = {
      b2_application_key    = "CONCEALED"
      b2_application_key_id = "STRING"
      b2_bucket_name        = "STRING"
      b2_endpoint           = "URL"
      fqdn_external         = "URL"
      fqdn_internal         = "URL"
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

variable "resources_homelab" {
  default     = ["b2", "cloudflare", "resend", "tailscale"]
  description = "List of all available homelab resources that can be enabled via the resources input"
  type        = list(string)
}

variable "resources_services" {
  default     = ["b2", "resend", "tailscale"]
  description = "List of all available services resources that can be enabled via the resources input"
  type        = list(string)
}
