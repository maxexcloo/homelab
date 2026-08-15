provider "onepassword" {
  connect_token = var.onepassword_connect_token
  connect_url   = var.onepassword_connect_url
}

data "onepassword_vault" "talos_recovery" {
  name = local.home_cluster.recovery_vault
}
