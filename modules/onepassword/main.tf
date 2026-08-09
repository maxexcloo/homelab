data "external" "inventory" {
  program = [
    "uv",
    "run",
    "${path.root}/scripts/reconcile_onepassword.py",
    "--inventory",
  ]

  query = {
    field_names = jsonencode(var.field_names)
    titles      = jsonencode(var.titles)
    vault_id    = var.vault_id
  }
}
