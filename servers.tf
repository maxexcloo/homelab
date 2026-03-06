data "bitwarden_folder" "servers" {
  search = "Servers"
}

data "external" "bw_servers" {
  program = [
    "mise", "exec", "--", "bash", "-c",
    <<-EOF
    SESSION_FILE=".bitwarden/session"
    
    if [ -f "$SESSION_FILE" ]; then
      export BW_SESSION=$(cat "$SESSION_FILE")
    fi

    if ! bw status --session "$BW_SESSION" &>/dev/null | grep -q '"status":"unlocked"'; then
      bw config server "$BW_URL" &>/dev/null || true
      bw login --apikey &>/dev/null || true
      
      export BW_SESSION="$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null)"
      
      if [ -n "$BW_SESSION" ]; then
        echo "$BW_SESSION" > "$SESSION_FILE"
      else
        echo "Failed to unlock. You may be rate-limited by Vaultwarden or missing credentials." >&2
        exit 1
      fi
    fi

    bw sync --session "$BW_SESSION" &>/dev/null || true
    ITEMS=$(bw list items --folderid "${data.bitwarden_folder.servers.id}" --session "$BW_SESSION" 2>/dev/null)
    
    # Check if ITEMS is empty or just an empty JSON array '[]'
    if [[ -z "$ITEMS" || "$ITEMS" =~ ^[[:space:]]*\[\][[:space:]]*$ ]]; then
      echo "Error: No items found in Vaultwarden folder. The folder might be empty, or sync failed." >&2
      exit 1
    fi
    
    echo "$ITEMS" | jq -c '{items: tostring}'
    EOF
  ]
}

locals {
  _servers = {
    for v in jsondecode(data.external.bw_servers.result.items) : v.name => merge(
      {
        fields   = v.fields
        fqdn     = length(split("-", v.name)) > 2 ? "${join("-", slice(split("-", v.name), 2, length(split("-", v.name))))}.${split("-", v.name)[1]}" : split("-", v.name)[1]
        id       = v.id
        name     = length(split("-", v.name)) > 2 ? join("-", slice(split("-", v.name), 2, length(split("-", v.name)))) : split("-", v.name)[1]
        password = v.login.password != null ? v.login.password : ""
        region   = split("-", v.name)[1]
        slug     = length(split("-", v.name)) > 2 ? "${split("-", v.name)[1]}-${join("-", slice(split("-", v.name), 2, length(split("-", v.name))))}" : split("-", v.name)[1]
        type     = split("-", v.name)[0]
        urls     = try([for uri in v.login.uris : uri.uri], [])
        username = v.login.username != null ? v.login.username : ""
      },
      var.server_defaults,
      {
        for field in v.fields : field.name => field.value
        if contains(keys(var.server_defaults), field.name)
      }
    )
  }

  servers = {
    for k, v in local._servers : k => merge(
      v,
      {
        fqdn_external = "${v.fqdn}.${var.defaults.domain_external}"
        fqdn_internal = "${v.fqdn}.${var.defaults.domain_internal}"
        password_hash = try(htpasswd_password.server[k].sha512, "")
        resources     = local.servers_resources[k]
        ssh_keys      = data.github_user.default.ssh_keys

        private_address = try(
          local.unifi_clients[v.slug].local_dns_record,
          null
        )

        private_ipv4 = try(
          local.unifi_clients[v.slug].fixed_ip,
          null
        )

        public_address = try(
          coalesce(
            v.public_address,
            try(local._servers[v.parent].public_address, null)
          ),
          null
        )

        public_ipv4 = try(
          coalesce(
            v.public_ipv4,
            try(local._servers[v.parent].public_ipv4, null)
          ),
          null
        )

        public_ipv6 = try(
          coalesce(
            v.public_ipv6,
            try(local._servers[v.parent].public_ipv6, null)
          ),
          null
        )
      },
      # Backblaze B2 resources
      local.servers_resources[k].b2 ? {
        b2_application_key_id        = b2_application_key.server[k].application_key_id
        b2_application_key_sensitive = b2_application_key.server[k].application_key
        b2_bucket_name               = b2_bucket.server[k].bucket_name
        b2_endpoint                  = replace(data.b2_account_info.default.s3_api_url, "https://", "")
      } : {},
      # Cloudflare resources
      local.servers_resources[k].cloudflare ? {
        cloudflare_account_token_sensitive = cloudflare_account_token.server[k].value
      } : {},
      # Cloudflared resources
      local.servers_resources[k].cloudflared ? {
        cloudflared_tunnel_token_sensitive = data.cloudflare_zero_trust_tunnel_cloudflared_token.server[k].token
      } : {},
      # Resend resources
      local.servers_resources[k].resend ? {
        resend_api_key_sensitive = jsondecode(restapi_object.resend_api_key_server[k].create_response).token
      } : {},
      # Tailscale resources
      local.servers_resources[k].tailscale ? {
        tailscale_auth_key_sensitive = tailscale_tailnet_key.server[k].key
        tailscale_ipv4               = try(local.tailscale_device_addresses[v.slug].ipv4, null)
        tailscale_ipv6               = try(local.tailscale_device_addresses[v.slug].ipv6, null)
      } : {}
    )
  }

  servers_resources = {
    for k, v in local._servers : k => {
      for resource in var.server_resources : resource => contains(try(split(",", replace(v.resources, " ", "")), []), resource)
    }
  }

  servers_urls = {
    #   for k, v in local.servers : k => [
    #     for key in sort(keys(v)) : merge(
    #       {
    #         href = format(
    #           "%s%s",
    #           can(cidrhost("${v[key]}/128", 0)) ? "[${v[key]}]" : v[key],
    #           v.management_port != null ? ":${v.management_port}" : ""
    #         )
    #         label = key
    #       },
    #       key == "fqdn_internal" ? { primary = true } : {}
    #     )
    #     if can(regex(var.url_field_pattern, key)) && v[key] != null
    #   ]
  }
}

output "servers" {
  value     = keys(local._servers)
  sensitive = false
}
