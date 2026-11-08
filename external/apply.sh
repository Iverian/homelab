#!/bin/sh
set -eu
cd "$(dirname "$0")"
stage=${1:---stage}
case "$stage" in --stage|--tailscale-only|--services-only) ;; *) exit 2;; esac
backup=/var/backups/external-hardening
install -d -m 0700 "$backup"
if [ ! -e "$backup/frps.toml" ]; then
    cp -a /etc/frp/frps.toml "$backup/frps.toml"
    cp -a /etc/systemd/system/frps.service "$backup/frps.service"
fi
getent passwd frps >/dev/null || useradd --system --home-dir /nonexistent --shell /usr/sbin/nologin frps
chown root:frps /etc/frp/secret
chmod 0750 /etc/frp/secret
chown root:frps /etc/frp/secret/*
chmod 0640 /etc/frp/secret/*
install -d /usr/local/libexec /etc/systemd/system/frps.service.d /etc/systemd/system/nftables.service.d /etc/systemd/journald.conf.d
install -m 0644 frps.toml /etc/frp/frps.toml
/usr/local/bin/frps verify -c /etc/frp/frps.toml
install -m 0755 proxy-policy.py /usr/local/libexec/frps-policy.py
install -m 0755 health-check.py /usr/local/libexec/external-health.py
install -m 0644 systemd/frps-hardening.conf /etc/systemd/system/frps.service.d/hardening.conf
install -m 0644 systemd/nftables-keep-tailscale.conf /etc/systemd/system/nftables.service.d/keep-tailscale.conf
install -m 0644 systemd/frps-policy.service systemd/external-health.service systemd/external-health.timer /etc/systemd/system/
install -m 0644 52-security-upgrades /etc/apt/apt.conf.d/52-security-upgrades
printf '[Journal]\nStorage=persistent\nSystemMaxUse=128M\nSystemKeepFree=256M\nMaxRetentionSec=14day\n' > /etc/systemd/journald.conf.d/retention.conf
if [ "$stage" != --services-only ]; then
install -m 0644 nftables.conf /etc/nftables.conf
if [ "$stage" = --stage ]; then
    sed -i '/iifname "tailscale0" tcp dport 22 accept/a\        tcp dport 22 accept comment "temporary: pending Tailscale verification"' /etc/nftables.conf
else
    tailscale status --json | python3 -c 'import json,sys; s=json.load(sys.stdin); assert s["BackendState"] == "Running" and s["Self"]["Online"]'
fi
nft -c -f /etc/nftables.conf
fi
systemctl daemon-reload
systemctl enable frps-policy.service
systemctl restart frps-policy.service
systemctl restart frps.service
systemctl is-active --quiet frps.service
if [ "$stage" != --services-only ]; then
systemctl enable nftables.service
nft -f /etc/nftables.conf
systemctl start nftables.service
fi
systemctl enable --now apt-daily.timer apt-daily-upgrade.timer external-health.timer
systemctl restart systemd-journald
