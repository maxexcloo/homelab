locals {
  duplicate_items   = jsondecode(data.external.inventory.result.duplicates)
  existing_fields   = jsondecode(data.external.inventory.result.existing_fields)
  missing_items     = jsondecode(data.external.inventory.result.missing)
  onepassword_items = jsondecode(data.external.inventory.result.item_ids)
}
