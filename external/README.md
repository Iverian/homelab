## External host

Debian 13 at `external.lan`, Tailscale
`homelab-external`. This host is not a NixOS flake output.

SSH uses the existing OpenSSH keys, only over `tailscale0`. Tailscale SSH is
not enabled. From a tailnet device: `ssh iverian@homelab-external`.
Provider console: root, password stored in SOPS as `externalRootPassword`.
Root SSH and all SSH password authentication remain disabled.

## Configuration

- `frps.toml`: public TCP 80/443/7000, mTLS and token file.
- `proxy-policy.py`: fail-closed NewProxy policy; exactly seven subdomains,
  HTTP and HTTPS each, fixed names; no custom domains, groups, TCP/UDP proxies.
  `maxPortsPerClient` alone is not a limit on HTTP proxy count.
- `systemd/frps-hardening.conf`: unprivileged service, only bind-service capability,
  read-only filesystem, 256 MiB memory high / 384 MiB maximum, 128 tasks.
- `nftables.conf`: input/forward default drop; public 80/443/7000, SSH only on
  Tailscale, DHCP and ICMP allowed. UDP 41641 is locally allowed for Tailscale;
  the current cloud firewall can keep blocking it (DERP fallback).
  Changes replace only `external_filter`, preserving Tailscale tables.
- `52-security-upgrades`: daily Debian security updates, no automatic reboot.
  FRP and Tailscale upstream releases need separate maintenance.
- `external-health.timer`: every five minutes checks services, listeners,
  Tailscale online status, FRP memory/restarts, certificates (30-day threshold),
  and reboot requirement. Results go to the persistent journal and systemd
  failure state. No external notification destination is configured.

## Applying

Prerequisites: nftables, unattended-upgrades, Python 3, OpenSSL, Tailscale from
its official Debian repository, existing `/etc/frp/secret` credentials.
No plaintext secrets are stored here or sent in process arguments.

From a machine already in the tailnet:

```sh
EXTERNAL_HOST=homelab-external just external-apply --services-only
EXTERNAL_HOST=homelab-external just external-apply --tailscale-only
```

If the local machine has no Tailscale, use the existing homelab as a transport:

```sh
EXTERNAL_HOST=homelab-external EXTERNAL_JUMP=iverian@homelab.lan just external-apply --services-only
```

With `EXTERNAL_JUMP`, the target address is resolved at runtime using
`tailscale ip` on the jump host; MagicDNS need not be enabled in its OS resolver.

The SSH host key is checked under the existing `external.lan` alias. The
services-only mode never writes or applies firewall rules. The explicit
`--stage` mode permits public SSH temporarily and must not be used for normal
maintenance. Before the first `--tailscale-only` application, verify a new SSH
session through Tailscale and schedule a timed firewall rollback. Cancel the
rollback only after another independent SSH connection succeeds.

Apply client HTTP proxies on homelab with `nix flake check`, `just plan`, and
`just apply`. They send PROXY v2 to the external Envoy Gateway HTTP listener on port 8080; the existing
HTTPRoute redirects to HTTPS, preserving the path and query string.

## Verification and recovery

```sh
sudo nft list table inet external_filter
sudo systemctl start external-health.service
sudo journalctl -u external-health.service -n 20
sudo systemctl show frps -p User -p NoNewPrivileges -p MemoryCurrent -p NRestarts
sudo journalctl -u frps -u frps-policy --since '10 minutes ago'
sudo unattended-upgrade --dry-run --debug
```

Confirm all 14 FRP registrations and seven HTTP redirects after changes. Test
HTTPS using the public IP with proper SNI. A fresh public SSH connection must
fail, while a fresh connection to the Tailscale address succeeds.

Initial FRP config/unit backups are in `/var/backups/external-hardening`.
From the provider console, emergency access can be restored temporarily with
`nft insert rule inet external_filter input tcp dport 22 accept`.
This is intentionally not persistent; repair Tailscale and reload nftables to
remove the exception. The cloud firewall must also permit TCP 22 for recovery.
