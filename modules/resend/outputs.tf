output "tokens" {
  description = "Resend API tokens keyed by item"
  sensitive   = true

  value = {
    for item_key, item in restapi_object.api_key :
    item_key => jsondecode(item.create_response).token
  }
}
