locals {
  generated_bytes = {
    for credential_key, generator in var.generators : credential_key => generator
    if contains(["base64", "hex"], generator.type)
  }

  generated_passwords = {
    for credential_key, generator in var.generators : credential_key => generator
    if generator.type == "alphanumeric"
  }

  generated_x509 = {
    for credential_key, generator in var.generators : credential_key => generator
    if generator.type == "x509"
  }

  values = merge(
    {
      for credential_key, generator in local.generated_bytes :
      credential_key => generator.type == "hex" ? random_id.generated[credential_key].hex : random_id.generated[credential_key].b64_std
    },
    {
      for credential_key in keys(local.generated_passwords) :
      credential_key => random_password.generated[credential_key].result
    },
  )
}
