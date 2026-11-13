#!/bin/sh

set -eu

title="OpenTofu"
vault="Homelab"

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
  "resend_api_key[password]=" \
  "tailscale_oauth_client_id[text]=" \
  "tailscale_oauth_client_secret[password]=" \
  "tailscale_tailnet[text]=" \
  "truenas_connections[password]=" \
  "unifi_api[url]=" \
  "unifi_api_key[password]="

items="$(op item list --format json --vault "${vault}")"
if ! printf '%s' "${items}" | jq -e --arg title "${title}" 'any(.[]; .title == $title)' >/dev/null; then
  op item create \
    --category "API Credential" \
    --title "${title}" \
    --vault "${vault}" \
    "notesPlain=Provider environment for the homelab OpenTofu root." \
    "$@" \
    >/dev/null
  echo "Created ${vault}/${title}. Populate every field before planning or applying."
  exit 0
fi

# Add only absent fields, empty, so existing values are never overwritten.
labels="$(op item get "${title}" --format json --vault "${vault}" | jq -r '.fields[].label')"
for field do
  shift
  printf '%s\n' "${labels}" | grep -Fqx "${field%%\[*}" || set -- "$@" "${field}"
done
if [ "$#" -eq 0 ]; then
  echo "${vault}/${title} has every field."
  exit 0
fi
op item edit "${title}" --vault "${vault}" "$@" >/dev/null
echo "Added $# empty fields to ${vault}/${title}. Populate them before planning or applying."
