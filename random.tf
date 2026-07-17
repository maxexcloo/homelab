locals {
  # Byte credentials use random_id so hex/base64 lengths mean bytes. Password
  # credentials use random_password for character and special-character controls.
  random_server_credentials = {
    for credential_entry in flatten([
      for server_key, server in local.servers_model : [
        for credential_name, generator in server.credentials.generated : {
          generator = generator
          key       = "${server_key}-${credential_name}"
        }
      ]
    ]) : credential_entry.key => credential_entry.generator
  }

  random_service_credentials = {
    for credential_entry in flatten([
      for service_key, service in local.services_model : [
        for credential_name, generator in service.credentials.generated : {
          generator = generator
          key       = "${service_key}-${credential_name}"
        }
      ]
    ]) : credential_entry.key => credential_entry.generator
  }

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
    if contains(["alphanumeric", "string"], generator.type)
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
    if contains(["alphanumeric", "string"], generator.type)
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

moved {
  from = random_password.server["au"]
  to   = random_password.server_secret["au-password"]
}

moved {
  from = random_password.server["au-bazzite"]
  to   = random_password.server_secret["au-bazzite-password"]
}

moved {
  from = random_password.server["au-haos"]
  to   = random_password.server_secret["au-haos-password"]
}

moved {
  from = random_password.server["au-hsp"]
  to   = random_password.server_secret["au-hsp-password"]
}

moved {
  from = random_password.server["au-truenas"]
  to   = random_password.server_secret["au-truenas-password"]
}

moved {
  from = random_password.server["au-truenas-openchamber"]
  to   = random_password.server_secret["au-truenas-openchamber-password"]
}

moved {
  from = random_password.server["us-hotdog"]
  to   = random_password.server_secret["us-hotdog-password"]
}

moved {
  from = random_password.service["aiometadata-au-truenas"]
  to   = random_password.service_secret["aiometadata-au-truenas-password"]
}

moved {
  from = random_password.service["aiostreams-au-truenas"]
  to   = random_password.service_secret["aiostreams-au-truenas-password"]
}

moved {
  from = random_password.service["beszel-au-truenas"]
  to   = random_password.service_secret["beszel-au-truenas-password"]
}

moved {
  from = random_password.service["bichon-au-truenas"]
  to   = random_password.service_secret["bichon-au-truenas-password"]
}

moved {
  from = random_password.service["grimmory-au-truenas"]
  to   = random_password.service_secret["grimmory-au-truenas-password"]
}

moved {
  from = random_password.service["immich-au-truenas"]
  to   = random_password.service_secret["immich-au-truenas-password"]
}

moved {
  from = random_password.service["larapaper-au-truenas"]
  to   = random_password.service_secret["larapaper-au-truenas-password"]
}

moved {
  from = random_password.service["linkwarden-au-truenas"]
  to   = random_password.service_secret["linkwarden-au-truenas-password"]
}

moved {
  from = random_password.service["miniflux-au-truenas"]
  to   = random_password.service_secret["miniflux-au-truenas-password"]
}

moved {
  from = random_password.service["papra-au-truenas"]
  to   = random_password.service_secret["papra-au-truenas-password"]
}

moved {
  from = random_password.service["pocket-id-au-truenas"]
  to   = random_password.service_secret["pocket-id-au-truenas-password"]
}

moved {
  from = random_password.service["romm-au-truenas"]
  to   = random_password.service_secret["romm-au-truenas-password"]
}

moved {
  from = random_password.service["shelfmark-au-truenas"]
  to   = random_password.service_secret["shelfmark-au-truenas-password"]
}

moved {
  from = random_password.service["syncthing-au-truenas"]
  to   = random_password.service_secret["syncthing-au-truenas-password"]
}
