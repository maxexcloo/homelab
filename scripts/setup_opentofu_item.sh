#!/bin/sh

set -eu

unset OP_CONNECT_HOST OP_CONNECT_TOKEN

if op item get "OpenTofu" --vault "Homelab" >/dev/null 2>&1; then
  echo "The Homelab/OpenTofu item already exists."
  exit 0
fi

op item create \
  --category "API Credential" \
  --title "OpenTofu" \
  --vault "Homelab" \
  "b2_application_key[password]=" \
  "b2_application_key_id[text]=" \
  "cloudflare_api_key[password]=" \
  "cloudflare_email[email]=" \
  "google_credentials[password]=" \
  "notesPlain=Provider environment for the homelab OpenTofu root." \
  "oci_fingerprint[text]=" \
  "oci_private_key_base64[password]=" \
  "oci_tenancy_ocid[text]=" \
  "oci_user_ocid[text]=" \
  "op_connect_host[url]=" \
  "op_connect_token[password]=" \
  "resend_api_key[password]=" \
  "tailscale_oauth_client_id[text]=" \
  "tailscale_oauth_client_secret[password]=" \
  "tailscale_tailnet[text]=" \
  "truenas_api_key[password]=" \
  "truenas_url[url]=" \
  "unifi_api[url]=" \
  "unifi_api_key[password]=" \
  >/dev/null

echo "Created Homelab/OpenTofu. Populate every field before planning or applying."
