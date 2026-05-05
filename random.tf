locals {
  # Byte secrets use random_id so hex/base64 lengths mean bytes. Password
  # secrets use random_password for character and special-character controls.
  random_service_secret_bytes = {
    for secret_config in flatten([
      for service_key, service in local.services_input_targets : [
        for secret in service.features.secrets : {
          byte_length = secret.bootstrap_length
          key         = "${service_key}-${secret.name}"
        }
        if contains(["hex", "base64"], try(secret.bootstrap_type, ""))
      ]
    ]) : secret_config.key => secret_config
  }

  random_service_secret_passwords = {
    for secret_config in flatten([
      for service_key, service in local.services_input_targets : [
        for secret in service.features.secrets : {
          key     = "${service_key}-${secret.name}"
          length  = secret.bootstrap_length
          special = try(secret.bootstrap_type, "") == "string"
        }
        if contains(["string", "alphanumeric"], try(secret.bootstrap_type, ""))
      ]
    ]) : secret_config.key => secret_config
  }
}

resource "random_id" "service_secret" {
  for_each = local.random_service_secret_bytes

  byte_length = each.value.byte_length
}

resource "random_password" "server" {
  for_each = local.servers_by_feature.password

  length = 32
}

resource "random_password" "service" {
  for_each = local.services_by_feature.password

  length = 32
}

resource "random_password" "service_secret" {
  for_each = local.random_service_secret_passwords

  length  = each.value.length
  special = each.value.special
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
