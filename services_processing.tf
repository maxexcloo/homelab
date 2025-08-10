# Processing phase - Extract fields and compute final values for services

locals {
  # Complete services structure with computed fields
  services = {
    for k, v in local.services_discovered : k => merge(
      v,                                    # Base metadata (id, name, platform)
      local.services_onepassword_fields[k], # 1Password fields
      # Computed fields can be added here as needed
      {
        # Resource-generated fields
        b2_application_key    = null
        b2_application_key_id = null
        b2_bucket_name        = null
        b2_endpoint           = replace(data.b2_account_info.default.s3_api_url, "https://", "")
        fqdn_external         = null
        fqdn_internal         = null
        resend_api_key        = null
      }
    ) if contains(keys(local.services_onepassword_fields), k)
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
