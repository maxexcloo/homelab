# Small composition module: encrypt content first, then write the encrypted
# payload to GitHub with a stable file resource.
module "sops_encrypt" {
  source = "../sops_encrypt"

  age_public_key = var.age_public_key
  content_base64 = var.content_base64
  content_type   = var.content_type
  debug_path     = var.debug_path
  filename       = var.file
}

resource "github_repository_file" "file" {
  commit_message      = var.commit_message
  content             = module.sops_encrypt.encrypted_content
  file                = var.file
  overwrite_on_create = true
  repository          = var.repository
}
