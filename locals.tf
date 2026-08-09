locals {
  defaults = provider::deepmerge::mergo(
    yamldecode(file("${path.module}/data/config.yaml")),
    yamldecode(file("${path.module}/data/defaults.yaml")),
  )

  render_json_template_expression_pattern     = "/\\$\\{([^}]*)\\}/"
  render_json_template_expression_replacement = "$${substr(jsonencode(tostring($1)), 1, length(jsonencode(tostring($1))) - 2)}"
}
