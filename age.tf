resource "shell_sensitive_script" "age_homelab" {
  for_each = local.homelab_discovered

  lifecycle_commands {
    create = <<-EOF
      KEYPAIR=$(age-keygen 2>/dev/null)
      PRIVATE_KEY=$(echo "$KEYPAIR" | grep "^AGE-SECRET-KEY" | head -n1)
      PUBLIC_KEY=$(echo "$KEYPAIR" | grep "# public key:" | sed "s/# public key: //" | head -n1)
      jq -n --arg private "$PRIVATE_KEY" --arg public "$PUBLIC_KEY" '{"private_key": $private, "public_key": $public}'
    EOF
    delete = "true"
  }
}
