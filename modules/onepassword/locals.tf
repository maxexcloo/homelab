locals {
  _duplicate_items = [
    for item_key, items in local._search_results : item_key
    if length(items) > 1
  ]

  _existing_ids = {
    for item_key, items in local._search_results :
    item_key => length(items) == 1 ? one(items).id : null
  }

  _existing_items = {
    for item_key, item_id in local._existing_ids : item_key => item_id
    if item_id != null
  }

  _item_payloads = {
    for item_key, payload in var.payloads : item_key => merge(
      payload,
      {
        id = try(local._existing_ids[item_key], null)

        vault = {
          id = var.vault_id
        }
      },
    )
  }

  _search_results = {
    for item_key, search in data.http.search :
    item_key => jsondecode(search.response_body)
  }

  existing_fields = {
    for item_key, item in data.http.item : item_key => {
      for field in jsondecode(item.response_body).fields :
      field.id => try(field.value, "")
      if try(field.value != null && field.value != "", false)
    }
  }
}
