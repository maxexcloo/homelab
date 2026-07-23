locals {
  _random_server_credential_bytes = {
    for credential_key, generator in local.random_server_credentials : credential_key => {
      byte_length = generator.length
    }
    if contains(["base64", "hex"], generator.type)
  }

  _random_server_credential_passwords = {
    for credential_key, generator in local.random_server_credentials : credential_key => {
      length = generator.length
    }
    if generator.type == "alphanumeric"
  }

  _random_service_credential_bytes = {
    for credential_key, generator in local.random_service_credentials : credential_key => {
      byte_length = generator.length
    }
    if contains(["base64", "hex"], generator.type)
  }

  _random_service_credential_passwords = {
    for credential_key, generator in local.random_service_credentials : credential_key => {
      length = generator.length
    }
    if generator.type == "alphanumeric"
  }

  random_server_credentials = merge({}, [
    for server_key, server in local.servers_model : {
      for credential_name, generator in server.credentials.generated :
      "${server_key}-${credential_name}" => generator
      if contains(["alphanumeric", "base64", "hex"], generator.type)
    }
  ]...)

  random_service_credentials = merge({}, [
    for service_key, service in local.services_model : {
      for credential_name, generator in service.credentials.generated :
      "${service_key}-${credential_name}" => generator
      if contains(["alphanumeric", "base64", "hex"], generator.type)
    }
  ]...)
}

resource "random_id" "server_secret" {
  for_each = local._random_server_credential_bytes

  byte_length = each.value.byte_length
}

resource "random_id" "service_secret" {
  for_each = local._random_service_credential_bytes

  byte_length = each.value.byte_length
}

moved {
  from = random_id.service_secret["auth-au-hsp-cookie_secret"]
  to   = random_id.service_secret["oauth2-proxy-au-hsp-cookie_secret"]
}

moved {
  from = random_id.service_secret["auth-au-truenas-cookie_secret"]
  to   = random_id.service_secret["oauth2-proxy-au-truenas-cookie_secret"]
}

resource "random_password" "server_secret" {
  for_each = local._random_server_credential_passwords

  length  = each.value.length
  special = false
}

resource "random_password" "service_secret" {
  for_each = local._random_service_credential_passwords

  length  = each.value.length
  special = false
}

resource "random_string" "b2_server" {
  for_each = local.servers_model_by_feature.object_storage

  length  = 6
  special = false
  upper   = false
}

resource "random_string" "b2_service" {
  for_each = local.services_model_by_feature.object_storage

  length  = 6
  special = false
  upper   = false
}
