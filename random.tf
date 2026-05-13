locals {
  # Byte secrets use random_id so hex/base64 lengths mean bytes. Password
  # secrets use random_password for character and special-character controls.
  random_server_secret_bytes = {
    for secret in flatten([
      for server_key, server in local.servers_model : [
        for secret in server.secrets : {
          byte_length = secret.bootstrap_length
          key         = "${server_key}-${secret.name}"
        }
        if secret.bootstrap_type != null && contains(["hex", "base64"], secret.bootstrap_type)
      ]
    ]) : secret.key => secret
  }

  random_server_secret_passwords = {
    for secret in flatten([
      for server_key, server in local.servers_model : [
        for secret in server.secrets : {
          key    = "${server_key}-${secret.name}"
          length = secret.bootstrap_length
        }
        if secret.bootstrap_type != null && contains(["string", "alphanumeric"], secret.bootstrap_type)
      ]
    ]) : secret.key => secret
  }

  random_service_secret_bytes = {
    for secret in flatten([
      for service_key, service in local.services_model : [
        for secret in service.secrets : {
          byte_length = secret.bootstrap_length
          key         = "${service_key}-${secret.name}"
        }
        if secret.bootstrap_type != null && contains(["hex", "base64"], secret.bootstrap_type)
      ]
    ]) : secret.key => secret
  }

  random_service_secret_passwords = {
    for secret in flatten([
      for service_key, service in local.services_model : [
        for secret in service.secrets : {
          key    = "${service_key}-${secret.name}"
          length = secret.bootstrap_length
        }
        if secret.bootstrap_type != null && contains(["string", "alphanumeric"], secret.bootstrap_type)
      ]
    ]) : secret.key => secret
  }
}

resource "random_id" "server_secret" {
  for_each = local.random_server_secret_bytes

  byte_length = each.value.byte_length
}

resource "random_id" "service_secret" {
  for_each = local.random_service_secret_bytes

  byte_length = each.value.byte_length
}

resource "random_password" "server" {
  for_each = local.servers_by_feature.password

  length  = 32
  special = false
}

resource "random_password" "server_komodo_passkey" {
  for_each = local.servers_model

  length  = 32
  special = false
}

resource "random_password" "server_secret" {
  for_each = local.random_server_secret_passwords

  length  = each.value.length
  special = false
}

resource "random_password" "service" {
  for_each = local.services_by_feature.password

  length  = 32
  special = false
}

resource "random_password" "service_secret" {
  for_each = local.random_service_secret_passwords

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
