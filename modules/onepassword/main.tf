data "external" "inventory" {
  count = length(var.titles) > 0 ? 1 : 0

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
