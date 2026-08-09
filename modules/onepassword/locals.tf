locals {
  _duplicate_items  = local._inventory != null ? jsondecode(local._inventory.duplicates) : []
  _inventory        = try(data.external.inventory["default"].result, null)
  _missing_items    = local._inventory != null ? jsondecode(local._inventory.missing) : []
  existing_fields   = local._inventory != null ? jsondecode(local._inventory.existing_fields) : {}
  onepassword_items = local._inventory != null ? jsondecode(local._inventory.item_ids) : {}
}
