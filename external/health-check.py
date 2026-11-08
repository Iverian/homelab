#!/usr/bin/env python3
"""Local health checks; failures surface in systemd and the persistent journal."""
import datetime
import json
import pathlib
import socket
import subprocess
import sys

problems = []

def output(*args):
    return subprocess.run(args, capture_output=True, text=True)

for name in ('frps', 'frps-policy', 'tailscaled', 'nftables', 'ssh'):
    if output('systemctl', 'is-active', '--quiet', name).returncode:
        problems.append(f'{name} is not active')
for port in (80, 443, 7000, 9001):
    try:
        with socket.create_connection(('localhost', port), timeout=3):
            pass
    except OSError:
        problems.append(f'listener {port} unavailable')
for filename in ('server-cert.pem', 'ca.pem'):
    if output('openssl', 'x509', '-checkend', '2592000', '-noout', '-in', '/etc/frp/secret/' + filename).returncode:
        problems.append(f'{filename} expires within 30 days or cannot be read')
props = dict(line.split('=', 1) for line in output('systemctl', 'show', 'frps', '-p', 'NRestarts', '-p', 'MemoryCurrent').stdout.splitlines())
if int(props.get('MemoryCurrent', '0')) > 256 * 1024 * 1024:
    problems.append('frps memory exceeds 256 MiB')
state = pathlib.Path('/var/lib/external-health/restarts')
restarts = int(props.get('NRestarts', '0'))
if state.exists() and restarts > int(state.read_text()):
    problems.append('frps restarted since previous check')
state.write_text(str(restarts))
installed_kernel = pathlib.Path('/vmlinuz').resolve().name.removeprefix('vmlinuz-')
running_kernel = output('uname', '-r').stdout.strip()
if pathlib.Path('/var/run/reboot-required').exists() or (installed_kernel and installed_kernel != running_kernel):
    problems.append('security updates require reboot')
try:
    status = json.loads(output('tailscale', 'status', '--json').stdout)
    if status.get('BackendState') != 'Running' or not status.get('Self', {}).get('Online'):
        problems.append('Tailscale is not online')
    if expiry := status.get('Self', {}).get('KeyExpiry'):
        remaining = datetime.datetime.fromisoformat(expiry.replace('Z', '+00:00')) - datetime.datetime.now(datetime.timezone.utc)
        if remaining.days < 30:
            problems.append('Tailscale node key expires within 30 days')
except (ValueError, TypeError):
    problems.append('cannot read Tailscale state')
for issue in problems:
    print('WARNING:', issue, flush=True)
if not problems:
    print('Host checks OK', flush=True)
sys.exit(bool(problems))
