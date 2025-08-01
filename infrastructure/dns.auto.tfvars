# DNS Zone Configuration
# This file contains DNS zone settings and manual DNS records

dns_zones = {
  "excloo.com" = {
    enabled         = true
    proxied_default = true
    
    # Manual DNS records (MX, TXT, special CNAMEs, etc.)
    records = [
      {
        name     = "@"
        type     = "MX"
        content  = "in1-smtp.messagingengine.com"
        priority = 10
      },
      {
        name     = "@"
        type     = "MX"
        content  = "in2-smtp.messagingengine.com"
        priority = 20
      },
      {
        name    = "@"
        type    = "TXT"
        content = "v=spf1 include:spf.messagingengine.com ?all"
      },
      {
        name    = "_github-pages-challenge-maxexcloo"
        type    = "TXT"
        content = "8140efead95e8b57bc46473cbddae9"
      },
      {
        name    = "fm1._domainkey"
        type    = "CNAME"
        content = "fm1.excloo.com.dkim.fmhosted.com"
      }
    ]
  }
  
  "excloo.net" = {
    enabled         = true
    proxied_default = true
    records         = []
  }
  
  "excloo.dev" = {
    enabled         = true
    proxied_default = false  # Internal domain, no proxy
    records         = []
  }
}
