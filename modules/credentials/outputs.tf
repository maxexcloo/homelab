output "hashes" {
  description = "Bcrypt hashes of selected generated scalar credentials"
  sensitive   = true

  value = {
    for credential_key in var.hashes :
    credential_key => htpasswd_password.generated[credential_key].bcrypt
  }
}

output "passwords" {
  description = "Selected plaintext passwords and their bcrypt hashes keyed by item"
  sensitive   = true

  value = {
    for item_key in var.passwords : item_key => {
      hash  = htpasswd_password.password[item_key].bcrypt
      value = try(var.password_overrides[item_key], local.values["${item_key}-password"])
    }
  }
}

output "values" {
  description = "Generated scalar credential values keyed by compound credential key"
  sensitive   = true
  value       = local.values
}

output "x509" {
  description = "Generated certificates and private keys keyed by compound credential key"
  sensitive   = true

  value = {
    for credential_key in keys(local._generated_x509) : credential_key => {
      certificate = tls_self_signed_cert.generated[credential_key].cert_pem
      private_key = tls_private_key.generated[credential_key].private_key_pem
    }
  }
}
