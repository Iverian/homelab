#!/usr/bin/env python3
"""Copy reviewed non-secret configuration; send the sudo password only on stdin."""
import ipaddress
import json
import os
import shlex
import subprocess
import sys
import tarfile
import tempfile

hostname = os.environ.get('EXTERNAL_HOST', 'homelab-external')
host = 'iverian@' + hostname
stage = sys.argv[1] if len(sys.argv) > 1 else '--services-only'
if stage not in ('--stage', '--tailscale-only', '--services-only'):
    raise SystemExit('expected --services-only, --stage or --tailscale-only')
ssh = ['ssh', '-F', '/dev/null', '-o', 'BatchMode=yes', '-o', 'HostKeyAlias=external.lan']
if jump := os.environ.get('EXTERNAL_JUMP'):
    target = subprocess.check_output(
        ['ssh', '-F', '/dev/null', '-o', 'BatchMode=yes', jump,
         'tailscale ip -4 ' + shlex.quote(hostname)], text=True).strip()
    address = ipaddress.IPv4Address(target)
    ssh += ['-o', 'ProxyCommand=ssh -F /dev/null -o BatchMode=yes -W '
            + shlex.quote(f'{address}:%p') + ' ' + shlex.quote(jump)]
ssh += [host]
if stage == '--tailscale-only':
    connection = subprocess.check_output(ssh + ['printf "%s" "$SSH_CONNECTION"']).decode().split()
    destination = ipaddress.ip_address(connection[2])
    status = json.loads(subprocess.check_output(ssh + ['tailscale status --json']))
    addresses = {ipaddress.ip_address(value) for value in status.get('Self', {}).get('TailscaleIPs', [])}
    if status.get('BackendState') != 'Running' or destination not in addresses:
        raise SystemExit('Refusing to close public SSH: reconnect using the Tailscale destination first')
with tempfile.TemporaryFile() as archive:
    with tarfile.open(fileobj=archive, mode='w') as tar:
        tar.add('external', arcname='external')
    archive.seek(0)
    remote = subprocess.check_output(ssh + ['mktemp -d /tmp/external-config.XXXXXXXX']).decode().strip()
    try:
        subprocess.run(ssh + ['tar -xf - -C ' + shlex.quote(remote)], stdin=archive, check=True)
        pw = subprocess.check_output(['sops', '-d', '--extract', '["externalPassword"]', 'main.sops.yaml']).strip()
        subprocess.run(ssh + ["sudo -S -p '' sh " + shlex.quote(remote + '/external/apply.sh') + ' ' + shlex.quote(stage)], input=pw+b'\n', check=True)
    finally:
        subprocess.run(ssh + ['rm -rf -- ' + shlex.quote(remote)], check=True)
