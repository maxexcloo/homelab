locals {
  _service_credential_generators = merge(
    merge({}, [
      for service_key, service in local.services_model : {
        for credential_name, generator in service.credentials.generated :
        "${service_key}-${credential_name}" => generator
        if contains(["alphanumeric", "base64", "hex"], generator.type)
      }
    ]...),
    local.services_model_x509_credentials,
  )

  _service_password_overrides = {
    for service_key, fields in local.onepassword_service_existing_fields :
    service_key => fields.password
    if try(fields.password, "") != ""
  }
}

module "credentials" {
  source = "../credentials"

  generators         = nonsensitive(local._service_credential_generators)
  organization       = local.defaults.organization.name
  password_overrides = local._service_password_overrides
  passwords = nonsensitive([
    for service_key, service in local.services_model_by_feature.password : service_key
    if service.credentials.source == "service"
  ])
}
