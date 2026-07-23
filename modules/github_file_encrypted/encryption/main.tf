resource "shell_sensitive_script" "encrypt" {
  environment = {
    AGE_PUBLIC_KEY = var.age_public_key
    CONTENT        = sensitive(var.content_base64)
    CONTENT_TYPE   = var.content_type
    DEBUG_PATH     = var.debug_path
    FILENAME       = var.filename
    SOPS_CONFIG    = "/dev/null"
  }

  lifecycle_commands {
    create = sensitive(local.script)
    delete = "true"
    read   = sensitive(local.script)
    update = sensitive(local.script)
  }

  triggers = {
    age_public_key_hash = sha256(var.age_public_key)
    content_hash        = sha256(var.content_base64)
    content_type        = var.content_type
    filename_hash       = sha256(var.filename)
    script_hash         = local.script_hash
  }

  lifecycle {
    ignore_changes = [lifecycle_commands]
  }
}
