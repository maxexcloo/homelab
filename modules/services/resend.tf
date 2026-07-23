# Service keys use the expanded service-target key, so each deployment target
# gets its own Resend credential.
resource "restapi_object" "resend_api_key_service" {
  for_each = local.services_model_by_feature.mail

  id_attribute              = "id"
  ignore_all_server_changes = true
  path                      = "/api-keys"
  provider                  = restapi.resend
  read_path                 = "/api-keys"

  data = jsonencode({
    name = each.key
  })

  read_search = {
    query_string = ""
    results_key  = "data"
    search_key   = "name"
    search_value = each.key
  }
}
