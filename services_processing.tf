# Processing phase - Extract fields and compute final values for services

locals {
  # Extract 1Password fields for each service item
  services_onepassword_fields = {
    for k, v in local.services_discovered : k => merge(
      # Extract input section fields
      {
        for field in try(data.onepassword_item.services_details[k].section[index(try(data.onepassword_item.services_details[k].section[*].label, []), "input")].field, []) :
        field.label => field.value == "-" ? null : field.value
      },
      # Extract output section fields
      {
        for field in try(data.onepassword_item.services_details[k].section[index(try(data.onepassword_item.services_details[k].section[*].label, []), "output")].field, []) :
        field.label => field.value == "-" ? null : field.value
      }
    ) if try(data.onepassword_item.services_details[k], null) != null
  }

  # Complete services structure with computed fields
  services = {
    for k, v in local.services_discovered : k => merge(
      v,                                    # Base metadata (id, name, platform)
      local.services_onepassword_fields[k], # 1Password fields
      # Computed fields can be added here as needed
      {
        # URL field for 1Password item
        url = try(local.services_onepassword_fields[k].url, null)

        # Example computed fields for services (uncomment as needed):
        # endpoint = "https://${v.name}.${var.domain_external}"
        # api_key  = random_password.service_api_key[k].result
        # status   = "active"
      }
    ) if contains(keys(local.services_onepassword_fields), k)
  }
}
