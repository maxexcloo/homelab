#!/bin/sh

set -eu

set -- \
  "b2_application_key[password]=" \
  "b2_application_key_id[text]=" \
  "cloudflare_api_key[password]=" \
  "cloudflare_email[email]=" \
  "control_d_api_key[password]=" \
  "google_credentials[password]=" \
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
  "truenas_connections[password]=" \
  "unifi_api[url]=" \
  "unifi_api_key[password]="

items="$(op item list --format json --vault "Homelab")"
if ! printf '%s' "${items}" | jq -e 'any(.[]; .title == "OpenTofu")' >/dev/null; then
  op item create \
    --category "API Credential" \
    --title "OpenTofu" \
    --vault "Homelab" \
    "notesPlain=Provider environment for the homelab OpenTofu root." \
    "$@" \
    >/dev/null
  echo "Created Homelab/OpenTofu. Populate every field before planning or applying."
  exit 0
fi

# Add only absent fields, empty, so existing values are never overwritten.
labels="$(op item get "OpenTofu" --format json --vault "Homelab" | jq -r '.fields[].label')"
for field do
  shift
  printf '%s\n' "${labels}" | grep -Fqx "${field%%\[*}" || set -- "$@" "${field}"
done
if [ "$#" -eq 0 ]; then
  echo "Homelab/OpenTofu has every field."
  exit 0
fi
op item edit "OpenTofu" --vault "Homelab" "$@" >/dev/null
echo "Added $# empty fields to Homelab/OpenTofu. Populate them before planning or applying."
