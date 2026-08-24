data "cloudflare_dns_records" "bestmates_acme_challenge" {
  type    = "TXT"
  zone_id = data.cloudflare_zone.default["bestmates.xyz"].zone_id
  name = {
    exact = "_acme-challenge.bestmates.xyz"
  }
}

import {
  id = "${data.cloudflare_zone.default["bestmates.xyz"].zone_id}/${one(data.cloudflare_dns_records.bestmates_acme_challenge.result).id}"
  to = cloudflare_dns_record.all["acme-delegation/bestmates.xyz"]
}
