import {
  id = "1bebf339e22bd127a20b0711"
  to = b2_bucket.application["syd/beszel"]
}

import {
  id = "zones/${data.cloudflare_zone.configured["excloo.com"].zone_id}/5b81fd9c04714199b57e69326b7eea37"
  to = cloudflare_ruleset.waf
}
