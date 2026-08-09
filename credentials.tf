locals {
  _server_credential_generators = merge(
    merge({}, [
      for server_key, server in local.servers_model : {
        for credential_name, generator in server.credentials.generated :
        "${server_key}-${credential_name}" => generator
        if(
          credential_name == "password" &&
          server.features.bootstrap &&
          server.platform != "truenas"
        )
      }
    ]...),
    local.servers_model_x509_credentials,
  )

  _server_onepassword_generators = {
    for server_key, server in local.servers_model : server_key => {
      for credential_name, generator in server.credentials.generated :
      credential_name => generator
      if(
        generator.type != "x509" &&
        !(
          credential_name == "password" &&
          server.features.bootstrap &&
          server.platform != "truenas"
        )
      )
    }
  }

  _server_password_overrides = {
    for server_key, fields in local.onepassword_server_existing_fields :
    server_key => fields.password
    if(
      local.servers_model[server_key].features.bootstrap &&
      local.servers_model[server_key].platform != "truenas" &&
      try(fields.password, "") != ""
    )
  }

  _service_credential_generators = merge(
    merge({}, [
      for service_key, service in local.services_model : {
        for credential_name, generator in service.credentials.generated :
        "${service_key}-${credential_name}" => generator
        if contains(local._service_provider_credential_names[service_key], credential_name)
      }
    ]...),
    local.services_model_x509_credentials,
  )

  _service_onepassword_generators = {
    for service_key, service in local.services_model : service_key => {
      for credential_name, generator in service.credentials.generated :
      credential_name => generator
      if(
        generator.type != "x509" &&
        !contains(local._service_provider_credential_names[service_key], credential_name)
      )
    }
  }

  _service_provider_credential_names = {
    for service_key, service in local.services_model : service_key => toset([
      for credential_name in keys(service.credentials.fields) : credential_name
      if anytrue(flatten([
        for route in service.routing.routes : [
          for rule in try(route.cloudflare_waf_rules, []) :
          strcontains(rule.expression, format("$${service.runtime.credentials.%s}", credential_name))
        ]
      ]))
    ])
  }
}

module "server_credentials" {
  source = "./modules/credentials"

  generators         = nonsensitive(local._server_credential_generators)
  organisation       = local.defaults.organisation.name
  password_overrides = local._server_password_overrides

  passwords = nonsensitive([
    for server_key, server in local.servers_model_by_feature.password : server_key
    if(
      server.features.bootstrap &&
      server.platform != "truenas"
    )
  ])
}

module "service_credentials" {
  source = "./modules/credentials"

  generators   = nonsensitive(local._service_credential_generators)
  organisation = local.defaults.organisation.name
}
