locals {
  defaults = provider::deepmerge::mergo(
    yamldecode(file("${path.module}/data/config.yml")),
    yamldecode(file("${path.module}/data/defaults.yml")),
  )

  # JSON-escape each templatestring() interpolation result before decoding
  # structured service and server data back into its original shape.
  render_json_template_expression_pattern     = "/\\$\\{([^}]*)\\}/"
  render_json_template_expression_replacement = "$${substr(jsonencode(tostring($1)), 1, length(jsonencode(tostring($1))) - 2)}"
}
