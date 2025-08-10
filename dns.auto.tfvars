# Non-sensitive DNS configuration
# This file contains DNS records for all managed zones and is safe to commit to version control

dns = {
  "bestmates.xyz" = [
    {
      content  = "hsp.au.excloo.net"
      name     = "@"
      type     = "CNAME"
      wildcard = true
    }
  ]
  "excloo.com" = [
    {
      content = "103.168.172.65"
      name    = "mail"
      type    = "A"
    },
    {
      content  = "hsp.au.excloo.net"
      name     = "@"
      type     = "CNAME"
      wildcard = true
    },
    {
      content = "fm1.excloo.com.dkim.fmhosted.com"
      name    = "fm1._domainkey"
      type    = "CNAME"
    },
    {
      content = "fm2.excloo.com.dkim.fmhosted.com"
      name    = "fm2._domainkey"
      type    = "CNAME"
    },
    {
      content = "fm3.excloo.com.dkim.fmhosted.com"
      name    = "fm3._domainkey"
      type    = "CNAME"
    },
    {
      content = "mesmtp.excloo.com.dkim.fmhosted.com"
      name    = "mesmtp._domainkey"
      type    = "CNAME"
    },
    {
      content  = "in1-smtp.messagingengine.com"
      name     = "@"
      priority = 10
      type     = "MX"
    },
    {
      content  = "in2-smtp.messagingengine.com"
      name     = "@"
      priority = 20
      type     = "MX"
    },
    {
      content = "\"v=DMARC1; p=none;\""
      name    = "@"
      type    = "TXT"
    },
    {
      content = "\"v=spf1 include:spf.messagingengine.com ?all\""
      name    = "@"
      type    = "TXT"
    }
  ]
  "excloo.dev" = []
  "excloo.net" = []
  "excloo.org" = [
    {
      content  = "hsp.au.excloo.net"
      name     = "@"
      type     = "CNAME"
      wildcard = true
    }
  ]
  "maxexcloo.com" = [
    {
      content  = "hsp.au.excloo.net"
      name     = "@"
      type     = "CNAME"
      wildcard = true
    }
  ]
  "schaefer.au" = [
    {
      content = "103.168.172.65"
      name    = "mail"
      type    = "A"
    },
    {
      content  = "hsp.au.excloo.net"
      name     = "@"
      type     = "CNAME"
      wildcard = true
    },
    {
      content = "fm1.schaefer.au.dkim.fmhosted.com"
      name    = "fm1._domainkey"
      type    = "CNAME"
    },
    {
      content = "fm2.schaefer.au.dkim.fmhosted.com"
      name    = "fm2._domainkey"
      type    = "CNAME"
    },
    {
      content = "fm3.schaefer.au.dkim.fmhosted.com"
      name    = "fm3._domainkey"
      type    = "CNAME"
    },
    {
      content = "mesmtp.schaefer.au.dkim.fmhosted.com"
      name    = "mesmtp._domainkey"
      type    = "CNAME"
    },
    {
      content  = "in1-smtp.messagingengine.com"
      name     = "@"
      priority = 10
      type     = "MX"
    },
    {
      content  = "in2-smtp.messagingengine.com"
      name     = "@"
      priority = 20
      type     = "MX"
    },
    {
      content = "\"v=DMARC1; p=none;\""
      name    = "@"
      type    = "TXT"
    },
    {
      content = "\"v=spf1 include:spf.messagingengine.com ?all\""
      name    = "@"
      type    = "TXT"
    }
  ]
}
