output "existing_fields" {
  description = "Existing non-empty fields keyed by item and stable field ID"
  sensitive   = true
  value       = local.existing_fields
}
