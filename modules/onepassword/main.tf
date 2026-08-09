data "external" "inventory" {
  for_each = length(var.titles) > 0 ? { default = true } : {}

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
