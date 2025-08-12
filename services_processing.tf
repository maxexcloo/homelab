# Processing phase - Extract fields and compute final values for services

locals {
  # Complete services structure with computed fields
  services = {
    for k, v in local.services_discovered : k => merge(
      v,                                    # Base metadata (id, name, platform)
      local.services_onepassword_fields[k], # 1Password fields
      # Computed fields
      {
        # Resource-generated fields (conditional based on service flags)
        b2_application_key    = null
        b2_application_key_id = null
        b2_bucket_name        = null
        b2_endpoint           = contains(try(local.services_flags[k].tags, []), "b2") ? replace(data.b2_account_info.default.s3_api_url, "https://", "") : null
        resend_api_key        = null

        # Service FQDNs (subdomains of first deployment target)
        fqdn_external = try(
          length(local.services_deployments[k].targets) > 0 ?
          local.homelab[local.services_deployments[k].targets[0]].fqdn_external : null,
          null
        )
        fqdn_internal = try(
          length(local.services_deployments[k].targets) > 0 ?
          local.homelab[local.services_deployments[k].targets[0]].fqdn_internal : null,
          null
        )

      }
    ) if contains(keys(local.services_onepassword_fields), k)
  }

  # Determine deployment targets for each service
  services_deployments = {
    for service_key, service in local.services_discovered : service_key => {
      deploy_to = nonsensitive(try(local.services_onepassword_fields_input_raw[service_key].deploy_to, null))

      targets = try(
        # If no deploy_to, no targets
        local.services_onepassword_fields[service_key].deploy_to == null || local.services_onepassword_fields[service_key].deploy_to == "-" ? [] :

        # Direct server reference (e.g., "vm-au-hsp")
        contains(keys(local.homelab_discovered), local.services_onepassword_fields[service_key].deploy_to) ?
        [local.services_onepassword_fields[service_key].deploy_to] :

        # Platform match (e.g., "platform:vm")
        startswith(local.services_onepassword_fields[service_key].deploy_to, "platform:") ? [
          for k, v in local.homelab_discovered : k
          if v.platform == trimprefix(local.services_onepassword_fields[service_key].deploy_to, "platform:")
        ] :

        # Region match (e.g., "region:au")
        startswith(local.services_onepassword_fields[service_key].deploy_to, "region:") ? [
          for k, v in local.homelab_discovered : k
          if v.region == trimprefix(local.services_onepassword_fields[service_key].deploy_to, "region:")
        ] :

        # Tag match using flags field (e.g., "tag:production")
        startswith(local.services_onepassword_fields[service_key].deploy_to, "tag:") ? [
          for k, v in local.homelab_discovered : k
          if contains(local.homelab_flags[k].tags, trimprefix(local.services_onepassword_fields[service_key].deploy_to, "tag:"))
        ] :

        # Default to empty if no match
        [],
        []
      )
    }
  }

  # Parse flags for services
  services_flags = {
    for k, v in local.services_discovered : k => {
      # Tags are all flags (services don't have resources like homelab items)
      tags = compact(split(",", replace(nonsensitive(try(local.services_onepassword_fields_input_raw[k].flags, "")), " ", "")))
    }
  }

  # Extract 1Password fields for each service item
  services_onepassword_fields = {
    for k, v in local.services_discovered : k => merge(
      # Extract input section fields (convert "-" to null for consistent processing)
      {
        for field in try(data.onepassword_item.services_details[k].section[index(try(data.onepassword_item.services_details[k].section[*].label, []), "input")].field, []) :
        field.label => field.value == "-" ? null : field.value
      },
      # Extract output section fields (convert "-" to null for consistent processing)
      {
        for field in try(data.onepassword_item.services_details[k].section[index(try(data.onepassword_item.services_details[k].section[*].label, []), "output")].field, []) :
        field.label => field.value == "-" ? null : field.value
      }
    ) if try(data.onepassword_item.services_details[k], null) != null
  }

  # Keep track of original input field values for sync
  services_onepassword_fields_input_raw = {
    for k, v in local.services_discovered : k => {
      for field in try(data.onepassword_item.services_details[k].section[index(try(data.onepassword_item.services_details[k].section[*].label, []), "input")].field, []) :
      field.label => field.value
    } if try(data.onepassword_item.services_details[k], null) != null
  }
}
