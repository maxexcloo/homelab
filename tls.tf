resource "tls_private_key" "server" {
  for_each = local.servers_model_x509_credentials

  algorithm = "ED25519"
}

resource "tls_private_key" "service" {
  for_each = local.services_model_x509_credentials

  algorithm = "ED25519"
}

resource "tls_self_signed_cert" "server" {
  for_each = local.servers_model_x509_credentials

  private_key_pem       = tls_private_key.server[each.key].private_key_pem
  validity_period_hours = each.value.validity_period_hours

  allowed_uses = [
    "client_auth",
    "digital_signature",
    "server_auth",
  ]

  subject {
    common_name  = each.value.common_name
    organization = local.defaults.organization.name
  }
}

resource "tls_self_signed_cert" "service" {
  for_each = local.services_model_x509_credentials

  private_key_pem       = tls_private_key.service[each.key].private_key_pem
  validity_period_hours = each.value.validity_period_hours

  allowed_uses = [
    "client_auth",
    "digital_signature",
    "server_auth",
  ]

  subject {
    common_name  = each.value.common_name
    organization = local.defaults.organization.name
  }
}
