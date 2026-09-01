moved {
  from = unifi_client.host["hass"]
  to   = unifi_client.host["84:47:09:67:c8:33"]
}

moved {
  from = unifi_client.host["kimbap"]
  to   = unifi_client.host["c8:ff:bf:01:52:e0"]
}

moved {
  # The motherboard and its existing UniFi client moved from Mandu to Bento.
  from = unifi_client.host["mandu"]
  to   = unifi_client.host["c8:ff:bf:0f:9f:d0"]
}

moved {
  from = unifi_client.host["taco"]
  to   = unifi_client.host["02:74:61:63:6f:01"]
}

import {
  id = "a531d41ab5c60781d7ab539da748ed00/cd3c10802744fc090567fc0cb8aff628"
  to = cloudflare_dns_record.managed["excloo.com-manual-CNAME-_acme-challenge.www.reddit"]
}

import {
  id = "a531d41ab5c60781d7ab539da748ed00/4285f34dc2448fb83eea59ff486de31e"
  to = cloudflare_dns_record.managed["excloo.com-manual-CNAME-status"]
}

import {
  id = "a531d41ab5c60781d7ab539da748ed00/230e706af06c21902a4410a4c5b6c32a"
  to = cloudflare_dns_record.managed["tunnel/hass/home-assistant.excloo.com"]
}
