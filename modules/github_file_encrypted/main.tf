module "sops_encrypt" {
  source = "./encryption"

  age_public_key = var.age_public_key
  content_base64 = var.content_base64
  content_type   = var.content_type
  debug_path     = var.debug_path
  filename       = var.file
}

resource "github_repository_file" "file" {
  commit_message      = var.commit_message
  content             = var.encrypt ? module.sops_encrypt.encrypted_content : sensitive(base64decode(var.content_base64))
  file                = var.file
  overwrite_on_create = true
  repository          = var.repository
}
