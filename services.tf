data "bitwarden_folder" "services" {
  search = "Services"
}

data "external" "bw_services" {
  program = [
    "mise", "exec", "--", "bash", "-c",
    <<-EOF
    bw config server "$BW_URL" &>/dev/null || true
    bw login --apikey &>/dev/null || true
    export BW_SESSION="$(bw unlock --passwordenv BW_PASSWORD --raw 2>/dev/null)"
    [ -n "$BW_SESSION" ] && bw sync --session "$BW_SESSION" &>/dev/null || true
    ITEMS=$(bw list items --folderid "${data.bitwarden_folder.services.id}" --session "$BW_SESSION" 2>/dev/null)
    echo "$${ITEMS:-[]}" | jq -c '{items: tostring}'
    EOF
  ]
}

locals {
  _services = {
    # for v in jsondecode(data.external.bw_services.result.items) : v.name => merge(
    #   {
    #     id       = v.id
    #     name     = join("-", slice(split("-", v.name), 1, length(split("-", v.name))))
    #     platform = split("-", v.name)[0]
    #     urls     = try([for uri in v.login.uris : uri.uri], [])
    #     fields   = { for field in v.fields : field.name => field.value }
    #   }
    # )
  }

  services = {
    for k, v in local._services : k => merge(
      v,
      {
        deployments = local.services_deployments[k]
        resources   = local.services_resources[k]
        url         = try(v.urls[0], null)
      },
      # Per-deployment fqdns merged at top level per target
      length(local.services_deployments[k]) > 0 ? {
        for target in local.services_deployments[k] : target => merge(
          !contains(try(split(",", replace(v.tags, " ", "")), []), "no_dns") ? {
            fqdn_external = "${v.name}.${local.servers[target].fqdn_external}"
            fqdn_internal = "${v.name}.${local.servers[target].fqdn_internal}"
          } : {}
        )
      } : {}
    )
  }

  services_deployments = {
    for k, v in local._services : k => distinct(flatten([
      for target in(v.deploy_to == null ? [] : split(",", replace(v.deploy_to, " ", ""))) : (
        target == "all" ? keys(local._servers) :
        startswith(target, "platform:") ? [
          for h_key, h_val in local._servers : h_key
          if h_val.platform == trimprefix(target, "platform:")
        ] :
        startswith(target, "region:") ? [
          for h_key, h_val in local._servers : h_key
          if h_val.region == trimprefix(target, "region:")
        ] :
        contains(keys(local._servers), target) ? [target] : []
      )
    ]))
  }

  services_instances = merge([
    for service_key, service in local.services : {
      for target in service.deployments : "${service.name}-${local.servers[target].slug}" => {
        server  = target
        service = service_key
      }
    }
  ]...)

  services_resources = {
    for k, v in local._services : k => {
      for resource in var.service_resources : resource => contains(try(split(",", replace(v.resources, " ", "")), []), resource)
    }
  }

  services_urls = {
    for k, v in local.services : k => concat(
      v.url != null ? [
        {
          href    = v.url
          label   = "url"
          primary = true
        }
      ] : [],
      flatten([
        for target, output in v : [
          for field in sort(keys(output)) : {
            href    = output[field]
            label   = "${field}_${target}"
            primary = field == "fqdn_internal" && v.url == null && target == keys(v)[0]
          }
          if can(regex(var.url_field_pattern, field)) && output[field] != null
        ]
      ])
    )
  }
}

output "services" {
  value     = keys(local._services)
  sensitive = false
}
