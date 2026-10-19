data "onepassword_item" "cloudflare_access" {
  title = "Cloudflare Access"
  vault = data.onepassword_vault.configured["cluster/${local.access.cloudflare_access.cluster}"].uuid
}

import {
  id = "vaults/${data.onepassword_item.cloudflare_access.vault}/items/${data.onepassword_item.cloudflare_access.uuid}"
  to = onepassword_item.cloudflare_access
}

import {
  id = "accounts/${data.cloudflare_account.default.id}/1b295422-1c33-4b28-a94f-8be3a4dffae4"
  to = cloudflare_zero_trust_access_identity_provider.pocket_id
}
