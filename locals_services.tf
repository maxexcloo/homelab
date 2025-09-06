locals {
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

  # Complete services data with structured input/output sections
  services = {
    for k, v in local.services_discovered : k => merge(
      v,
      {
        url = length(local.services_deployments[k]) > 0 ? "https://${k}.${local.homelab[local.services_deployments[k][0]].output.fqdn_external}" : null

        input = v.input
        output = length(local.services_deployments[k]) > 0 ? {
          for target in local.services_deployments[k] : "output-${target}" => merge(
            # Computed values for this target
            {
              b2_application_key    = null
              b2_application_key_id = null
              b2_bucket_name        = null
              b2_endpoint           = null
              database_password     = try(v.input.database_password, null)
              fqdn_external         = "${k}.${local.homelab[target].output.fqdn_external}"
              fqdn_internal         = "${k}.${local.homelab[target].output.fqdn_internal}"
              resend_api_key        = null
              secret_hash           = try(v.input.secret_hash, null)
            }
          )
        } : {}
      }
    )
  }


  # Determine which resources to create for each service
  services_resources = {
    for k, v in local.services_discovered : k => {
      for resource in var.resources_services : resource => contains(
        split(",", replace(try(v.input.resources, ""), " ", "")),
        resource
      )
    }
  }

  # Parse tags from space-separated input to array
  services_tags = {
    for k, v in local.services_discovered : k => try(
      v.input.tags != null ? split(",", replace(v.input.tags, " ", "")) : [],
      []
    )
  }
}
