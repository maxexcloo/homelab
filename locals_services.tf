locals {
  # Extract and normalize 1Password fields for each service
  services_onepassword = {
    for k, v in local.services_discovered : k => {
      # Merged fields with schema defaults (all fields guaranteed to exist)
      fields = merge(
        # Start with all schema fields set to null
        {
          for field_name, field_type in merge(
            var.onepassword_services_field_schema.input,
            var.onepassword_services_field_schema.output
          ) : field_name => null
        },
        # Override with actual input values (convert "-" to null)
        {
          for field in try(data.onepassword_item.services_details[k].section[
            index(try(data.onepassword_item.services_details[k].section[*].label, []), "input")
          ].field, []) : field.label => field.value == "-" ? null : field.value
        },
        # Override with actual output values (convert "-" to null)
        {
          for field in try(data.onepassword_item.services_details[k].section[
            index(try(data.onepassword_item.services_details[k].section[*].label, []), "output")
          ].field, []) : field.label => field.value == "-" ? null : field.value
        }
      )

      # Raw input fields for sync back to 1Password (preserves "-" values)
      input_raw = {
        for field in try(data.onepassword_item.services_details[k].section[
          index(try(data.onepassword_item.services_details[k].section[*].label, []), "input")
        ].field, []) : field.label => field.value
      }
    } if try(data.onepassword_item.services_details[k], null) != null
  }

  # Determine where each service should be deployed
  services_deployments = {
    for k, v in local.services_discovered : k => {
      # Store the raw deploy_to value for validation
      deploy_to = try(local.services_onepassword[k].fields.deploy_to, null)

      # Parse deployment targets based on deploy_to syntax
      targets = (
        # No deployment if deploy_to is null or empty
        local.services_onepassword[k].fields.deploy_to == null ? [] :

        # Direct server reference (e.g., "vm-au-hsp")
        contains(keys(local.homelab_discovered), local.services_onepassword[k].fields.deploy_to) ?
        [local.services_onepassword[k].fields.deploy_to] :

        # Platform match (e.g., "platform:vm")
        startswith(local.services_onepassword[k].fields.deploy_to, "platform:") ?
        [for h_key, h_val in local.homelab_discovered : h_key
        if h_val.platform == trimprefix(local.services_onepassword[k].fields.deploy_to, "platform:")] :

        # Region match (e.g., "region:au")
        startswith(local.services_onepassword[k].fields.deploy_to, "region:") ?
        [for h_key, h_val in local.homelab_discovered : h_key
        if h_val.region == trimprefix(local.services_onepassword[k].fields.deploy_to, "region:")] :

        # Tag match (e.g., "tag:production")
        startswith(local.services_onepassword[k].fields.deploy_to, "tag:") ?
        [for h_key, h_val in local.homelab : h_key
        if contains(h_val.tags, trimprefix(local.services_onepassword[k].fields.deploy_to, "tag:"))] :

        # Default to empty if no match
        []
      )
    } if contains(keys(local.services_onepassword), k)
  }

  # Determine which resources to create for each service
  # TODO: Parse from 1Password resources field once sensitive value limitation is resolved
  services_resources = {
    for k, v in local.services_discovered : k => {
      for resource in var.resources_services : resource => contains(
        try(var.default_services_resources[v.platform], []),
        resource
      )
    }
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
        tags = (
          local.services_onepassword[k].fields.tags != null ?
          split(",", replace(nonsensitive(local.services_onepassword[k].fields.tags), " ", "")) :
          []
        )

        # Service FQDNs (inherit from first deployment target)
        fqdn_external = try(
          length(local.services_deployments[k].targets) > 0 ?
          "${k}.${local.homelab[local.services_deployments[k].targets[0]].fqdn_external}" :
          null,
          null
        )

        fqdn_internal = try(
          length(local.services_deployments[k].targets) > 0 ?
          "${k}.${local.homelab[local.services_deployments[k].targets[0]].fqdn_internal}" :
          null,
          null
        )
      },

      # Layer 3: Resource-generated credentials (only if resource is enabled)
      # TODO: Implement service-specific resources when needed
      {
        # Backblaze B2 (placeholder - resources not yet implemented)
        b2_application_key    = null
        b2_application_key_id = null
        b2_bucket_name        = null
        b2_endpoint           = local.services_resources[k].b2 ? replace(data.b2_account_info.default.s3_api_url, "https://", "") : null

        # Resend (placeholder - resources not yet implemented)
        resend_api_key = null
      }
    ) if contains(keys(local.services_onepassword), k)
  }
}
