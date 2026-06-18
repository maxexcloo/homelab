locals {
  # Byte credentials use random_id so hex/base64 lengths mean bytes. Password
  # credentials use random_password for character and special-character controls.
  random_server_credential_bytes = {
    for field in flatten([
      for server_key, server in local.servers_model : [
        for field_name, field in server.credentials.fields : {
          byte_length = field.bootstrap_length
          key         = "${server_key}-${field_name}"
        }
        if(
          field.bootstrap_type != null &&
          contains(["hex", "base64"], field.bootstrap_type)
        )
      ]
    ]) : field.key => field
  }

  random_server_credential_passwords = {
    for field in flatten([
      for server_key, server in local.servers_model : [
        for field_name, field in server.credentials.fields : {
          key    = "${server_key}-${field_name}"
          length = field.bootstrap_length
        }
        if(
          field.bootstrap_type != null &&
          contains(["string", "alphanumeric"], field.bootstrap_type)
        )
      ]
    ]) : field.key => field
  }

  random_service_credential_bytes = {
    for field in flatten([
      for service_key, service in local.services_model : [
        for field_name, field in service.credentials.fields : {
          byte_length = field.bootstrap_length
          key         = "${service_key}-${field_name}"
        }
        if(
          field.bootstrap_type != null &&
          contains(["hex", "base64"], field.bootstrap_type)
        )
      ]
    ]) : field.key => field
  }

  random_service_credential_passwords = {
    for field in flatten([
      for service_key, service in local.services_model : [
        for field_name, field in service.credentials.fields : {
          key    = "${service_key}-${field_name}"
          length = field.bootstrap_length
        }
        if(
          field.bootstrap_type != null &&
          contains(["string", "alphanumeric"], field.bootstrap_type)
        )
      ]
    ]) : field.key => field
  }
}

resource "random_id" "server_secret" {
  for_each = local.random_server_credential_bytes

  byte_length = each.value.byte_length
}

resource "random_id" "service_secret" {
  for_each = local.random_service_credential_bytes

  byte_length = each.value.byte_length
}

resource "random_password" "server" {
  for_each = local.servers_by_feature.password

  length  = 32
  special = false
}

resource "random_password" "server_secret" {
  for_each = local.random_server_credential_passwords

  length  = each.value.length
  special = false
}

resource "random_password" "service" {
  for_each = local.services_by_feature.password

  length  = 32
  special = false
}

resource "random_password" "service_secret" {
  for_each = local.random_service_credential_passwords

  length  = each.value.length
  special = false
}

resource "random_string" "b2_server" {
  for_each = local.servers_by_feature.b2

  length  = 6
  special = false
  upper   = false
}

resource "random_string" "b2_service" {
  for_each = local.services_by_feature.b2

  length  = 6
  special = false
  upper   = false
}
