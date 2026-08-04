output "existing_fields" {
  description = "Existing non-empty fields keyed by item and stable field ID"
  sensitive   = true
  value       = local.existing_fields
}

output "item_ids" {
  description = "Non-secret item IDs keyed by resource key"

  value = nonsensitive({
    for item_key, item_id in local._existing_ids : item_key => item_id
    if item_id != null
  })

  precondition {
    condition     = length(local._duplicate_items) == 0
    error_message = "1Password item lookup is ambiguous: ${join(", ", nonsensitive(local._duplicate_items))}"
  }

  precondition {
    condition     = length(local._missing_items) == 0
    error_message = "1Password items are missing: ${join(", ", nonsensitive(local._missing_items))}"
  }
}
