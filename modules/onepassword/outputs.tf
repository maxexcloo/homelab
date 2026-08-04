output "existing_fields" {
  description = "Existing non-empty fields keyed by item and stable field ID"
  sensitive   = true
  value       = local.existing_fields
}

output "item_ids" {
  description = "Non-secret item IDs keyed by resource key"

  value = nonsensitive({
    for item_key, item in restapi_object.item : item_key => item.id
  })
}
