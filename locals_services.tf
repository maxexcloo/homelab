# Extract fields from 1Password sections
locals {
  _services_fields = {
    for k, v in local.services_discovered : k => {
      input_section  = try([for s in data.onepassword_item.service[k].section : s if s.label == "input"][0], null)
      output_section = try([for s in data.onepassword_item.service[k].section : s if s.label == "output"][0], null)
    } if try(data.onepassword_item.service[k], null) != null
  }

  # Complete services data with all fields merged and computed
  services = {
    for k, v in local.services_discovered : k => merge(
      # Base: Discovery metadata
      v,

      # Layer 1: All 1Password fields (guaranteed to exist with nulls)
      try(local.services_onepassword[k].fields, {}),

      # Layer 2: Computed fields
      {
        # Parse tags from comma-separated string
        tags = try(split(",", replace(local.services_onepassword[k].fields.tags, " ", "")), [])

        # Service FQDNs (inherit from first deployment target)
        fqdn_external = try("${k}.${local.homelab[local.services_deployments[k].targets[0]].fqdn_external}", null)
        fqdn_internal = try("${k}.${local.homelab[local.services_deployments[k].targets[0]].fqdn_internal}", null)
      },

      # Layer 3: Resource-generated credentials
      # TODO: Implement service-specific resources when needed
      local.services_resources[k].b2 ? {
        b2_endpoint = replace(data.b2_account_info.default.s3_api_url, "https://", "")
      } : {}
    ) if try(local.services_onepassword[k], null) != null
  }

  # Determine where each service should be deployed
  services_deployments = {
    for k, v in local.services_discovered : k => {
      # Store the raw deploy_to value for validation
      deploy_to = try(local.services_onepassword[k].fields.deploy_to, null)

      # Parse deployment targets based on deploy_to syntax
      targets = try(
        local.services_onepassword[k].fields.deploy_to == null ? [] :
        # Direct server reference
        lookup(local.homelab_discovered, local.services_onepassword[k].fields.deploy_to, null) != null ? [local.services_onepassword[k].fields.deploy_to] :
        # Platform/region/tag matches
        [for h_key, h_val in local.homelab_discovered : h_key
          if(startswith(local.services_onepassword[k].fields.deploy_to, "platform:") && h_val.platform == trimprefix(local.services_onepassword[k].fields.deploy_to, "platform:")) ||
          (startswith(local.services_onepassword[k].fields.deploy_to, "region:") && h_val.region == trimprefix(local.services_onepassword[k].fields.deploy_to, "region:")) ||
          (startswith(local.services_onepassword[k].fields.deploy_to, "tag:") && contains(try(local.homelab[h_key].tags, []), trimprefix(local.services_onepassword[k].fields.deploy_to, "tag:")))
        ],
        []
      )
    } if try(local.services_onepassword[k], null) != null
  }

  # Extract and normalize 1Password fields for each service
  services_onepassword = {
    for k, v in local._services_fields : k => {
      # Merged fields with schema defaults (all fields guaranteed to exist)
      fields = merge(
        # Start with all schema fields set to null
        {
          for field_name, field_type in merge(
            var.onepassword_services_field_schema.input,
            var.onepassword_services_field_schema.output
          ) : field_name => null
        },
        # Override with actual values (convert "-" to null)
        {
          for field in try(v.input_section.field, []) : field.label => field.value == "-" ? null : field.value
        },
        {
          for field in try(v.output_section.field, []) : field.label => field.value == "-" ? null : field.value
        }
      )

      # Raw input fields for sync back to 1Password (preserves "-" values)
      input_raw = {
        for field in try(v.input_section.field, []) : field.label => field.value
      }
    }
  }

  # Determine which resources to create for each service
  services_resources = {
    for k, v in local.services_discovered : k => {
      for resource in var.resources_services : resource =>
      contains(try(var.default_services_resources[v.platform], []), resource)
    }
  }
}
