# Retained Appliance Recovery

OpenTofu owns shared DNS, UniFi reservations, Tailscale policy, and one reusable
recovery key per retained machine. It does not own an appliance merely because
the machine appears in `data/machines.yaml`.

## HAOS

Home Assistant owns its application configuration and backups. Keep its backup
encryption material and emergency administrator access in 1Password. UniFi owns
the fixed `10.0.0.2` reservation and this repository owns its public DNS and
least-privilege ACME token. Rebuild the appliance first, restore a tested HAOS
backup, then re-enrol Tailscale using the recovery key stored under
`Tailscale Recovery Key: hass.mbk.excloo.net` in the Homelab vault.

## Hotdog

Hotdog owns its operating system, ZFS pool, SSH host keys, and Tailscale client.
TrueNAS owns the existing outbound replication jobs documented in
`truenas-ownership.md`. Keep the ZFS pool recovery details and hosting account
access in 1Password. Rebuild the host without creating an empty target dataset
over retained replicas, restore SSH and Tailscale access, and then validate the
existing TrueNAS replication jobs manually.

## Kimbap

TrueNAS owns its appliance configuration database, UPS and SMTP settings, ACME
authenticator, certificate, and replication credentials. Export its encrypted
configuration after material appliance changes and store the export outside Git
with its secret seed in 1Password. The management address `10.0.0.3/22` remains
the recovery path if the Services bridge fails.

## Mandu

Bazzite owns the gaming workstation operating system and application data.
Keep disk-encryption recovery material and platform account recovery in
1Password. Restore Bazzite, SSH access through the 1Password agent, and then its
existing Tailscale client; the managed key under `Tailscale Recovery Key: mandu.mbk.excloo.net` is for
re-enrolment rather than routine login.

## Ramen

UniFi owns the gateway configuration, firewall policies, VLANs, and controller
backup. Store exported controller backups and owner-account recovery outside
Git. This repository validates the Default and Services network contracts but
does not currently create or reorder firewall rules. Restore the controller
before relying on DHCP reservations or VLAN 4, then re-enrol Tailscale with the
recovery key under `Tailscale Recovery Key: ramen.mbk.excloo.net` if the gateway installation uses it.

## Shared rules

- SSH private keys stay in the 1Password SSH agent; rendered SSH configuration
  contains connection facts only.
- Existing appliance Tailscale clients are appliance-owned. Managed reusable
  keys are recovery material and do not force re-enrolment.
- Do not store appliance backups, private keys, API tokens, kubeconfigs, or
  recovery exports in this repository.
- Test restores separately from ordinary OpenTofu applies.
