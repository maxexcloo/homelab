locals {
  _defaults        = yamldecode(file("${path.module}/data/defaults.yml"))
  dns_defaults     = local._defaults.dns
  server_defaults  = local._defaults.servers
  service_defaults = local._defaults.services

  _dns_raw = {
    for filepath in fileset(path.module, "data/dns/*.yml") :
    filepath => yamldecode(file("${path.module}/${filepath}"))
  }

  defaults = {
    for k, v in local._defaults : k => v
    if !contains(["dns", "servers", "services"], k)
  }

  dns = {
    for filepath, data in local._dns_raw :
    data.name => try(data.records, [])
  }

  sops_encrypt_script = <<-EOT
    #!/bin/bash
    set -euo pipefail

    DATA="$(printf '%s' "$CONTENT" | base64 -d)"

    PREVIOUS_DATA=""
    if [ ! -t 0 ]; then
      PREVIOUS_DATA="$(cat || true)"
    fi

    HASH="$(printf '%s' "$DATA" | sha256sum | awk '{print $1}')"
    PREVIOUS_HASH="$(printf '%s' "$PREVIOUS_DATA" | jq -r '.hash // ""' 2>/dev/null || true)"

    if [ -n "$${DEBUG_PATH:-}" ]; then
      mkdir -p "$(dirname "$${DEBUG_PATH}")"
      printf '%s' "$DATA" > "$${DEBUG_PATH}"
    fi

    if [ -n "$PREVIOUS_DATA" ] && [ "$PREVIOUS_HASH" = "$HASH" ]; then
      printf '%s' "$PREVIOUS_DATA"
      exit 0
    fi

    if [ -z "$${CONTENT_TYPE:-}" ]; then
      jq -n --arg encrypted_content "$DATA" --arg hash "$HASH" '{encrypted_content: $encrypted_content, hash: $hash}'
      exit 0
    fi

    ENCRYPTED_CONTENT="$(printf '%s' "$DATA" | sops encrypt --age "$AGE_PUBLIC_KEY" --input-type "$CONTENT_TYPE" --output-type "$CONTENT_TYPE" /dev/stdin)"

    jq -n --arg encrypted_content "$ENCRYPTED_CONTENT" --arg hash "$HASH" '{encrypted_content: $encrypted_content, hash: $hash}'
  EOT
}

output "summary" {
  description = "Summary of infrastructure managed by OpenTofu"
  sensitive   = false

  value = {
    defaults = local.defaults
    servers  = keys(local.servers)
    services = keys(local.services)

    counts = {
      dns_records = length(local.dns_records_acme_delegation) + length(local.dns_records_manual) + length(local.dns_records_servers) + length(local.dns_records_services) + length(local.dns_records_services_fly) + length(local.dns_records_services_urls) + length(local.dns_records_wildcards)
      servers     = length(local.servers)
      services    = length(local.services)
    }
  }
}
