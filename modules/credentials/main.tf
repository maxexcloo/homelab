resource "random_id" "generated" {
  for_each = local._generated_bytes

  byte_length = each.value.length
}

resource "random_password" "generated" {
  for_each = local._generated_passwords

  length  = each.value.length
  special = false
}

resource "htpasswd_password" "generated" {
  for_each = var.hashes

  password = sensitive(local.values[each.key])
}

resource "htpasswd_password" "password" {
  for_each = var.passwords

  password = sensitive(try(
    var.password_overrides[each.key],
    local.values["${each.key}-password"],
  ))
}

resource "tls_private_key" "generated" {
  for_each = local._generated_x509

  algorithm = "ED25519"
}

resource "tls_self_signed_cert" "generated" {
  for_each = local._generated_x509

  private_key_pem       = tls_private_key.generated[each.key].private_key_pem
  validity_period_hours = each.value.validity_period_hours

  allowed_uses = [
    "client_auth",
    "digital_signature",
    "server_auth",
  ]

  subject {
    common_name  = each.value.common_name
    organization = var.organization
  }
}
