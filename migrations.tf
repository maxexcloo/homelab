moved {
  from = cloudflare_dns_record.managed["service/mercury/dsh"]
  to   = cloudflare_dns_record.managed["service/mercury/dsh/code.excloo.com"]
}

moved {
  from = cloudflare_dns_record.managed["service-acme/mercury/dsh"]
  to   = cloudflare_dns_record.managed["service-acme/mercury/dsh/code.excloo.com"]
}
