#!/usr/bin/env python3
"""Fail-closed FRP NewProxy allowlist; never log request bodies/secrets."""
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlsplit

SUBDOMAINS = frozenset(('auth', 'gitea', 'jellyfin', 'nextcloud', 'sync', 'home-assistant', 'foundry'))


def allowed(c):
    if not isinstance(c, dict):
        return False
    kind, domain = c.get('proxy_type'), c.get('subdomain')
    return (isinstance(kind, str) and isinstance(domain, str) and kind in ('http', 'https') and domain in SUBDOMAINS
            and c.get('proxy_name') == f'{domain}-{kind}'
            and not any(c.get(k) for k in ('custom_domains', 'locations', 'group', 'remote_port')))


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(5)

    def do_POST(self):
        valid = False
        try:
            url = urlsplit(self.path)
            length = int(self.headers.get('Content-Length', '0'))
            if url.path == '/handler' and parse_qs(url.query).get('op') == ['NewProxy'] and 0 < length <= 16384:
                valid = allowed(json.loads(self.rfile.read(length)).get('content'))
        except (ValueError, TypeError, AttributeError, TimeoutError):
            pass
        body = json.dumps({'reject': not valid, 'unchange': True,
                           'reject_reason': '' if valid else 'proxy outside homelab allowlist'}).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        if not valid:
            print('Rejected proxy registration outside allowlist', flush=True)

    def log_message(self, *_):
        pass


if __name__ == '__main__':
    HTTPServer(('localhost', 9001), Handler).serve_forever()
