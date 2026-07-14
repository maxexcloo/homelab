locals {
  # Byte credentials use random_id so hex/base64 lengths mean bytes. Password
  # credentials use random_password for character and special-character controls.
  random_server_credential_fields = {
    for field_entry in flatten([
      for server_key, server in local.servers_model : [
        for field_name, field in server.credentials.fields : {
          field = field
          key   = "${server_key}-${field_name}"
        }
      ]
    ]) : field_entry.key => field_entry.field
  }

  random_service_credential_fields = {
    for field_entry in flatten([
      for service_key, service in local.services_model : [
        for field_name, field in service.credentials.fields : {
          field = field
          key   = "${service_key}-${field_name}"
        }
      ]
    ]) : field_entry.key => field_entry.field
  }

  _random_server_credential_bytes = {
    for field_key, field in local.random_server_credential_fields : field_key => {
      byte_length = field.bootstrap_length
    }
    if(
      field.bootstrap_type != null &&
      contains(["hex", "base64"], field.bootstrap_type)
    )
  }

  _random_server_credential_passwords = {
    for field_key, field in local.random_server_credential_fields : field_key => {
      length = field.bootstrap_length
    }
    if(
      field.bootstrap_type != null &&
      contains(["string", "alphanumeric"], field.bootstrap_type)
    )
  }

  _random_service_credential_bytes = {
    for field_key, field in local.random_service_credential_fields : field_key => {
      byte_length = field.bootstrap_length
    }
    if(
      field.bootstrap_type != null &&
      contains(["hex", "base64"], field.bootstrap_type)
    )
  }

  _random_service_credential_passwords = {
    for field_key, field in local.random_service_credential_fields : field_key => {
      length = field.bootstrap_length
    }
    if(
      field.bootstrap_type != null &&
      contains(["string", "alphanumeric"], field.bootstrap_type)
    )
  }
}

resource "random_id" "server_secret" {
  for_each = local._random_server_credential_bytes

  byte_length = each.value.byte_length
}

resource "random_id" "service_secret" {
  for_each = local._random_service_credential_bytes

  byte_length = each.value.byte_length
}

resource "random_password" "server" {
  for_each = local.servers_model_by_feature.password

  length  = 32
  special = false
}

resource "random_password" "server_secret" {
  for_each = local._random_server_credential_passwords

  length  = each.value.length
  special = false
}

resource "random_password" "service" {
  for_each = local.services_model_by_feature.password

  length  = 32
  special = false
}

resource "random_password" "service_secret" {
  for_each = local._random_service_credential_passwords

  length  = each.value.length
  special = false
}

resource "random_string" "b2_server" {
  for_each = local.servers_model_by_feature.b2

  length  = 6
  special = false
  upper   = false
}

resource "random_string" "b2_service" {
  for_each = local.services_model_by_feature.b2

  length  = 6
  special = false
  upper   = false
}
