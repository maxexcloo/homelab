# The generic REST provider has no first-class Resend resource. read_search
# keeps API key creation idempotent by matching existing keys by name.
resource "restapi_object" "api_key" {
  for_each = var.items

  id_attribute              = "id"
  ignore_all_server_changes = true
  path                      = "/api-keys"
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
