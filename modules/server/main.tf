# Server Module - Main entry point

variable "name" {
  description = "Server name"
  type        = string
}

variable "config" {
  description = "Server configuration from 1Password"
  type        = any
}



locals {
  # Parse server configuration from 1Password sections
  sections = {
    for section in try(var.config.section, []) :
    section.label => {
      for field in section.field :
      field.label => field.value
    }
  }

  inputs  = try(local.sections.inputs, {})
  outputs = try(local.sections.outputs, {})

  # Extract server details
  short_name = replace(var.name, "server-", "")
  region     = try(split("-", local.short_name)[0], "")
  hostname   = try(split("-", local.short_name)[1], local.short_name)

  # Server type and platform
  type     = try(local.inputs.type, "physical")
  platform = try(local.inputs.platform, "ubuntu")
}

# Create server based on type
module "oci" {
  source = "./oci"
  count  = local.type == "oci" ? 1 : 0

  name       = var.name
  short_name = local.short_name
  region     = local.region
  hostname   = local.hostname
  config     = var.config
}

module "proxmox" {
  source = "./proxmox"
  count  = local.type == "proxmox" ? 1 : 0

  name       = var.name
  short_name = local.short_name
  region     = local.region
  hostname   = local.hostname
  config     = var.config
}

# Physical and VPS servers are managed externally
resource "null_resource" "physical" {
  count = local.type == "physical" || local.type == "vps" ? 1 : 0

  triggers = {
    name = var.name
    type = local.type
  }
}

# Outputs
output "server" {
  value = {
    name         = var.name
    short_name   = local.short_name
    region       = local.region
    hostname     = local.hostname
    type         = local.type
    platform     = local.platform
    public_ip    = try(module.oci[0].public_ip, module.proxmox[0].public_ip, local.outputs.public_ip, "")
    private_ip   = try(module.oci[0].private_ip, module.proxmox[0].private_ip, local.outputs.private_ip, "")
    tailscale_ip = local.outputs.tailscale_ip
  }
}