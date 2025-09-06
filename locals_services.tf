locals {
  # Complete services data with structured input/output sections
  services = {
    for k, v in local.services_discovered : k => merge(
      v,
      {
        input = v.input
        output = length(local.services_deployments[k]) > 0 ? {
          for target in local.services_deployments[k] : "output-${target}" => merge(
            # Computed values for this target
            {
              database_password = try(v.input.database_password, null)
              fqdn_external     = "${v.name}.${local.homelab[target].output.fqdn_external}"
              fqdn_internal     = "${v.name}.${local.homelab[target].output.fqdn_internal}"
              secret_hash       = try(v.input.secret_hash, null)
            }
          )
        } : {}
      }
    )
  }

  # Resolve deployment targets from deploy_to input
  services_deployments = {
    for k, v in local.services_discovered : k => (
      try(v.input.deploy_to, null) == null ? [] :
      # Deploy to all servers
      v.input.deploy_to == "all" ? keys(local.homelab_discovered) :
      # Direct server reference
      contains(keys(local.homelab_discovered), v.input.deploy_to) ? [v.input.deploy_to] :
      # Pattern-based matches
      [
        for h_key, h_val in local.homelab_discovered : h_key
        if(
          startswith(v.input.deploy_to, "platform:") && h_val.platform == trimprefix(v.input.deploy_to, "platform:") ||
          startswith(v.input.deploy_to, "region:") && h_val.region == trimprefix(v.input.deploy_to, "region:") ||
          startswith(v.input.deploy_to, "tag:") && contains(try(local.homelab_tags[h_key], []), trimprefix(v.input.deploy_to, "tag:"))
        )
      ]
    )
  }

  # Determine which resources to create for each service
  services_resources = {
    for k, v in local.services_discovered : k => {
      for resource in var.resources_services : resource => contains(try(split(",", replace(v.input.resources, " ", "")), []), resource)
    }
  }

  # Parse tags from input field
  services_tags = {
    for k, v in local.services_discovered : k => try(split(",", replace(v.input.tags, " ", "")), [])
  }
}
