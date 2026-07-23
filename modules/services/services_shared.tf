locals {
  _onepassword_integration_ready              = nonsensitive(var.integrations.onepassword.ready)
  _pocketid_integration_ready                 = nonsensitive(var.integrations.pocketid.ready)
  defaults                                    = var.defaults
  dns_input                                   = var.dns
  render_json_template_expression_pattern     = "/\\$\\{([^}]*)\\}/"
  render_json_template_expression_replacement = "$${substr(jsonencode(tostring($1)), 1, length(jsonencode(tostring($1))) - 2)}"
  servers_input                               = nonsensitive(var.servers.model.input)
  servers_model                               = nonsensitive(var.servers.model.servers)
  servers_render_servers                      = var.servers.render
}
