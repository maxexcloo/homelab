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

resource "restapi_object" "item" {
  for_each = var.enabled ? var.titles : {}

  data                    = sensitive(jsonencode(local._item_payloads[each.key]))
  id_attribute            = "id"
  ignore_server_additions = true
  path                    = "/v1/vaults/${var.vault_id}/items"
  read_path               = "/v1/vaults/${var.vault_id}/items/{id}"
  update_data             = sensitive(jsonencode(local._item_payloads[each.key]))

  lifecycle {
    prevent_destroy = true

    precondition {
      condition     = length(local._duplicate_items) == 0
      error_message = "1Password item lookup is ambiguous: ${join(", ", nonsensitive(local._duplicate_items))}"
    }
  }
}
