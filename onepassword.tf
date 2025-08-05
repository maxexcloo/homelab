data "external" "onepassword_vault_homelab_all" {
  program = ["sh", "-c", "op item list --format=json --vault='${var.onepassword_vault_homelab}' | jq -c '{stdout: (. | tostring)}'"]
}

data "external" "onepassword_vault_services_all" {
  program = ["sh", "-c", "op item list --format=json --vault='${var.onepassword_vault_services}' | jq -c '{stdout: (. | tostring)}'"]
}

data "onepassword_vault" "homelab" {
  name = var.onepassword_vault_homelab
}

data "onepassword_vault" "services" {
  name = var.onepassword_vault_services
}

locals {
  onepassword_vault_homelab_all = merge(
    local.onepassword_vault_homelab_routers,
    local.onepassword_vault_homelab_servers
  )

  onepassword_vault_homelab_routers = {
    for item in jsondecode(data.external.onepassword_vault_homelab_all.result.stdout) : item.title => {
      fqdn     = "${split("-", item.title)[1]}"
      id       = item.id
      name     = replace(item.title, "/^[a-z]+-/", "")
      platform = split("-", item.title)[0]
      region   = split("-", item.title)[1]
      title    = replace(item.title, "/^[a-z]+-/", "")
    } if can(regex("^[a-z]+-[a-z]+", item.title))
  }

  onepassword_vault_homelab_sections = {
    for key, item in local.onepassword_vault_homelab_all : key => {
      for section in try(data.onepassword_item.homelab[key].section, []) : section.label => {
        for field in section.field : field.label => coalesce(field.value, "-")
      }
    }
  }

  onepassword_vault_homelab_servers = {
    for item in jsondecode(data.external.onepassword_vault_homelab_all.result.stdout) : item.title => {
      fqdn     = "${replace(item.title, "/^[a-z]+-[a-z]+-/", "")}.${split("-", item.title)[1]}"
      id       = item.id
      name     = replace(item.title, "/^[a-z]+-[a-z]+-/", "")
      platform = split("-", item.title)[0]
      region   = split("-", item.title)[1]
      title    = replace(item.title, "/^[a-z]+-/", "")
    } if can(regex("^[a-z]+-[a-z]+-", item.title))
  }

  onepassword_vault_services_all = {
    for item in jsondecode(data.external.onepassword_vault_services_all.result.stdout) : item.title => {
      id       = item.id
      name     = replace(item.title, "/^[^-]*-/", "")
      platform = split("-", item.title)[0]
    } if can(regex("^[a-z]+-", item.title))
  }
}

output "onepassword_discovered" {
  value = {
    homelab  = keys(local.onepassword_vault_homelab_all)
    services = keys(local.onepassword_vault_services_all)
  }

  sensitive = false
}

data "onepassword_item" "homelab" {
  for_each = local.onepassword_vault_homelab_all

  title = each.key
  vault = data.onepassword_vault.homelab.uuid
}

data "onepassword_item" "services" {
  for_each = local.onepassword_vault_services_all

  title = each.key
  vault = data.onepassword_vault.services.uuid
}

import {
  for_each = local.onepassword_vault_homelab_all

  id = "vaults/${data.onepassword_vault.homelab.uuid}/items/${each.value.id}"
  to = onepassword_item.homelab[each.key]
}

import {
  for_each = local.onepassword_vault_services_all

  id = "vaults/${data.onepassword_vault.services.uuid}/items/${each.value.id}"
  to = onepassword_item.services[each.key]
}

resource "onepassword_item" "homelab" {
  for_each = local.onepassword_vault_homelab_all

  title    = data.onepassword_item.homelab[each.key].title
  url      = "${each.value.fqdn}.${var.domain_internal}"
  username = data.onepassword_item.homelab[each.key].username
  vault    = data.onepassword_vault.homelab.uuid

  section {
    label = "input"

    field {
      id    = "input.description"
      label = "description"
      type  = "STRING"
      value = try(local.onepassword_vault_homelab_sections[each.key].inputs.description, "-")
    }

    field {
      id    = "input.flags"
      label = "flags"
      type  = "STRING"
      value = try(local.onepassword_vault_homelab_sections[each.key].inputs.flags, "-")
    }

    field {
      id    = "input.parent"
      label = "parent"
      type  = "STRING"
      value = try(local.onepassword_vault_homelab_sections[each.key].inputs.parent, "-")
    }

    field {
      id    = "input.paths"
      label = "paths"
      type  = "STRING"
      value = try(local.onepassword_vault_homelab_sections[each.key].inputs.paths, data.onepassword_item.homelab[each.key].username == "root" ? "/${data.onepassword_item.homelab[each.key].username}" : "/home/${data.onepassword_item.homelab[each.key].username}")
    }

    field {
      id    = "input.public_address"
      label = "public_address"
      type  = "URL"
      value = try(local.onepassword_vault_homelab_sections[each.key].inputs.public_address, "-")
    }

    field {
      id    = "input.public_ipv4"
      label = "public_ipv4"
      type  = "URL"
      value = try(local.onepassword_vault_homelab_sections[each.key].inputs.public_ipv4, "-")
    }

    field {
      id    = "input.public_ipv6"
      label = "public_ipv6"
      type  = "URL"
      value = try(local.onepassword_vault_homelab_sections[each.key].inputs.public_ipv6, "-")
    }

    field {
      id    = "input.type"
      label = "type"
      type  = "STRING"
      value = try(local.onepassword_vault_homelab_sections[each.key].inputs.type, "-")
    }
  }

  section {
    label = "output"

    field {
      id    = "output.b2_application_key"
      label = "b2_application_key"
      type  = "CONCEALED"
      value = b2_application_key.homelab[each.key].application_key
    }

    field {
      id    = "output.b2_application_key_id"
      label = "b2_application_key_id"
      type  = "STRING"
      value = b2_application_key.homelab[each.key].application_key_id
    }

    field {
      id    = "output.b2_bucket_name"
      label = "b2_bucket_name"
      type  = "STRING"
      value = b2_bucket.homelab[each.key].bucket_name
    }

    field {
      id    = "output.b2_endpoint"
      label = "b2_endpoint"
      type  = "URL"
      value = replace(data.b2_account_info.default.s3_api_url, "https://", "")
    }

    field {
      id    = "output.cloudflare_account_token"
      label = "cloudflare_account_token"
      type  = "CONCEALED"
      value = "-"
    }

    field {
      id    = "output.cloudflare_tunnel_token"
      label = "cloudflare_tunnel_token"
      type  = "CONCEALED"
      value = "-"
    }

    field {
      id    = "output.fqdn_internal"
      label = "fqdn_internal"
      type  = "URL"
      value = "${each.value.fqdn}.${var.domain_internal}"
    }

    field {
      id    = "output.fqdn_external"
      label = "fqdn_external"
      type  = "URL"
      value = "${each.value.fqdn}.${var.domain_external}"
    }

    field {
      id    = "output.public_ipv4"
      label = "public_ipv4"
      type  = "URL"
      value = "-"
    }

    field {
      id    = "output.public_ipv6"
      label = "public_ipv6"
      type  = "URL"
      value = "-"
    }

    field {
      id    = "output.resend_api_key"
      label = "resend_api_key"
      type  = "CONCEALED"
      value = jsondecode(restapi_object.resend_api_key_homelab[each.key].create_response).token
    }

    field {
      id    = "output.region"
      label = "region"
      type  = "STRING"
      value = each.value.region
    }

    field {
      id    = "output.tailscale_auth_key"
      label = "tailscale_auth_key"
      type  = "CONCEALED"
      value = tailscale_tailnet_key.homelab[each.key].key
    }

    field {
      id    = "output.tailscale_ipv4"
      label = "tailscale_ipv4"
      type  = "URL"
      value = try(local.tailscale_devices[each.key].tailscale_ipv4, "-")
    }

    field {
      id    = "output.tailscale_ipv6"
      label = "tailscale_ipv6"
      type  = "URL"
      value = try(local.tailscale_devices[each.key].tailscale_ipv6, "-")
    }
  }
}

resource "onepassword_item" "services" {
  for_each = local.onepassword_vault_services_all

  title    = data.onepassword_item.services[each.key].title
  username = data.onepassword_item.services[each.key].username
  vault    = data.onepassword_vault.services.uuid
}
