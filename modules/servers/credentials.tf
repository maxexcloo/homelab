locals {
  _server_credential_generators = merge(
    merge({}, [
      for server_key, server in local.servers_model : {
        for credential_name, generator in server.credentials.generated :
        "${server_key}-${credential_name}" => generator
        if contains(["alphanumeric", "base64", "hex"], generator.type)
      }
    ]...),
    local.servers_model_x509_credentials,
  )

  _server_password_overrides = {
    for server_key, fields in local.onepassword_server_existing_fields :
    server_key => fields.password
    if try(fields.password, "") != ""
  }
}

module "credentials" {
  source = "../credentials"

  generators         = nonsensitive(local._server_credential_generators)
  organization       = local.defaults.organization.name
  password_overrides = local._server_password_overrides
  passwords          = nonsensitive(keys(local.servers_model_by_feature.password))
}
