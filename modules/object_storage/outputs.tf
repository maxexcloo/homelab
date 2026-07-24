output "items" {
  description = "Object storage credentials and bucket details keyed by item"
  sensitive   = true

  value = {
    for item_key in var.items : item_key => {
      access_key_id     = b2_application_key.item[item_key].application_key_id
      bucket            = b2_bucket.item[item_key].bucket_name
      endpoint          = var.endpoint
      secret_access_key = b2_application_key.item[item_key].application_key
    }
  }
}
