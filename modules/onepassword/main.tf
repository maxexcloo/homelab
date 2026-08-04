data "http" "search" {
  for_each = var.enabled ? var.titles : {}

  request_headers = var.request_headers
  url             = "${var.connect_url}/v1/vaults/${var.vault_id}/items?filter=${urlencode("title eq \"${each.value}\"")}"
}

data "http" "item" {
  for_each = var.enabled ? local._existing_items : {}

  request_headers = var.request_headers
  url             = "${var.connect_url}/v1/vaults/${var.vault_id}/items/${each.value}"
}
