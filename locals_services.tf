locals {
  # Complete services data with all fields merged and computed
  services = {
    for k, v in local.services_discovered : k => merge(
      # Base: Discovery metadata
      v,

      # 1Password fields (flattened from input/output sections)
      local.services_fields[k].input,
      local.services_fields[k].output,

      # Layer 1: Computed fields
      {
        fqdn_external = try("${k}.${local.homelab[local.services_deployments[k].targets[0]].fqdn_external}", null)
        fqdn_internal = try("${k}.${local.homelab[local.services_deployments[k].targets[0]].fqdn_internal}", null)
        tags          = try(split(",", replace(coalesce(local.services_fields[k].input.tags, ""), " ", "")), [])
      }
    ) if try(local.services_fields[k].input, null) != null
  }

  # Determine where each service should be deployed
  services_deployments = {
    for k, v in local.services_discovered : k => {
      # Store the raw deploy_to value for validation
      deploy_to = try(local.services_fields[k].input.deploy_to, null)

      # Parse deployment targets based on deploy_to syntax
      targets = try(
        local.services_fields[k].input.deploy_to == null ? [] :
        # Direct server reference
        lookup(local.homelab_discovered, local.services_fields[k].input.deploy_to, null) != null ? [local.services_fields[k].input.deploy_to] :
        # Platform/region/tag matches
        [for h_key, h_val in local.homelab_discovered : h_key
          if(startswith(local.services_fields[k].input.deploy_to, "platform:") && h_val.platform == trimprefix(local.services_fields[k].input.deploy_to, "platform:")) ||
          (startswith(local.services_fields[k].input.deploy_to, "region:") && h_val.region == trimprefix(local.services_fields[k].input.deploy_to, "region:")) ||
          (startswith(local.services_fields[k].input.deploy_to, "tag:") && contains(try(local.homelab[h_key].tags, []), trimprefix(local.services_fields[k].input.deploy_to, "tag:")))
        ],
        []
      )
    } if try(local.services_fields[k].input, null) != null
  }

  # Determine which resources to create for each service
  services_resources = {
    for k, v in local.services_discovered : k => {
      for resource in var.resources_services : resource => contains(try(var.resources_services_defaults[v.platform], []), resource)
    }
  }

  # Determine which tags to create for each service
  services_tags = {
    for k, v in local.services_discovered : k => {
      for tag in var.resources_services : tag => true
    }
  }
}
