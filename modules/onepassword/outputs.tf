output "existing_fields" {
  description = "Existing non-empty fields keyed by item and stable field ID"
  sensitive   = true
  value       = local.existing_fields
}

output "item_ids" {
  description = "Non-secret item IDs keyed by resource key"
  value       = nonsensitive(local.onepassword_items)

  precondition {
    condition     = length(local._duplicate_items) == 0
    error_message = "1Password item lookup is ambiguous: ${join(", ", nonsensitive(local._duplicate_items))}"
  }
}

output "missing_items" {
  description = "Item keys not present in the vault"
  value       = nonsensitive(local._missing_items)
}
