locals {
  _controld_dns_records_by_hostname = {
    for route in values(local.dns_model_routes) : route.hostname => {
      server_key = route.server_key
    }...
    if(
      route.hostname != null &&
      route.server_key != null &&
      try(module.servers.model.servers[route.server_key].features.tailscale, false)
    )
  }

  _controld_dns_records_model = {
    for hostname, records in local._controld_dns_records_by_hostname : hostname => {
      server_key = one(distinct(records[*].server_key))
    }
    if length(distinct(records[*].server_key)) == 1
  }

  _controld_dns_records_runtime = {
    for hostname, record in local._controld_dns_records_model : hostname => {
      ipv4 = module.servers.runtime[record.server_key].runtime.addresses.tailscale_ipv4
      ipv6 = module.servers.runtime[record.server_key].runtime.addresses.tailscale_ipv6

      data = jsonencode(merge(
        {
          do        = 2
          hostnames = [hostname]
          status    = 1
        },
        module.servers.runtime[record.server_key].runtime.addresses.tailscale_ipv4 != "" ? {
          via = module.servers.runtime[record.server_key].runtime.addresses.tailscale_ipv4
        } : {},
        module.servers.runtime[record.server_key].runtime.addresses.tailscale_ipv6 != "" ? {
          via_v6 = module.servers.runtime[record.server_key].runtime.addresses.tailscale_ipv6
        } : {},
      ))
    }
  }
}

resource "restapi_object" "controld_dns" {
  for_each = local._controld_dns_records_model

  data                    = local._controld_dns_records_runtime[each.key].data
  destroy_path            = "/profiles/${local.defaults.controld.profile_id}/rules/{id}"
  ignore_server_additions = true
  object_id               = each.key
  path                    = "/profiles/${local.defaults.controld.profile_id}/rules"
  provider                = restapi.controld
  read_path               = "/profiles/${local.defaults.controld.profile_id}/rules"
  update_data             = local._controld_dns_records_runtime[each.key].data
  update_path             = "/profiles/${local.defaults.controld.profile_id}/rules"

  read_search = {
    results_key  = "body/rules"
    search_key   = "PK"
    search_value = each.key
    search_patch = jsonencode([
      {
        op   = "add"
        path = "/hostnames"
        value = [
          each.key,
        ]
      },
      {
        from = "/action/do"
        op   = "move"
        path = "/do"
      },
      {
        from = "/action/status"
        op   = "move"
        path = "/status"
      },
      {
        from = "/action/via"
        op   = "move"
        path = "/via"
      },
      {
        from = "/action/via_v6"
        op   = "move"
        path = "/via_v6"
      },
      {
        op   = "remove"
        path = "/PK"
      },
      {
        op   = "remove"
        path = "/action"
      },
      {
        op   = "remove"
        path = "/group"
      },
      {
        op   = "remove"
        path = "/order"
      },
    ])
  }

  lifecycle {
    precondition {
      condition = (
        local._controld_dns_records_runtime[each.key].ipv4 != "" ||
        local._controld_dns_records_runtime[each.key].ipv6 != ""
      )
      error_message = "Control D hostname ${each.key} has no Tailscale address."
    }
  }
}

resource "terraform_data" "controld_validation" {
  lifecycle {
    precondition {
      condition = alltrue([
        for records in values(local._controld_dns_records_by_hostname) : length(distinct(records[*].server_key)) == 1
      ])
      error_message = "Control D hostnames must resolve to exactly one Tailscale server."
    }
  }
}
