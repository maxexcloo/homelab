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
  "excloo.dev" = [
    {
      content  = "feedback-smtp.ap-northeast-1.amazonses.com"
      name     = "resend"
      priority = 10
      type     = "MX"
    },
    {
      content = "\"v=DMARC1; p=none;\""
      name    = "_dmarc"
      type    = "TXT"
    },
    {
      content = "\"v=spf1 include:amazonses.com ~all\""
      name    = "resend"
      type    = "TXT"
    },
    {
      content = "\"p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQCxe6Q7J4m+QlXFTyLNSE8Dwzv8sI9K1KLcqOnnS+SUUP0mKagFqRzgUZgd8+3sfVJIqrJcEg/Y+dfdTtCJE78ryTq5WVpxOEmss1mkbIJlNPFRZHji9w6iQ3AdMOlM3GlFYdY5TK/tCW4zd7a0RLd3YzcY/S+TcpZ3GEeydDukewIDAQAB\""
      name    = "resend._domainkey"
      type    = "TXT"
    }
  ]
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
