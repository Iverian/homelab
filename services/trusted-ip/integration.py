"""Temporary external-Gateway routes; only synthetic benchmark IPs gain trust.

Run through `just trusted-ip-integration`. Never sends traffic to application
backends or changes trust for real users. All test resources are removed finally.
"""
import concurrent.futures
import http.client
import json
from pathlib import Path
import socket
import ssl
import struct
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parents[2]
NS = "envoy-gateway-system"
NAME = "trusted-ip-probe-" + uuid.uuid4().hex[:8]
HOST = NAME + ".iverian.ru"
IP = "198.18.10.10"
OTHER_IP = "198.18.10.11"
IP6 = "2001:db8:100::10"


def kubectl(*args, payload=None):
    return subprocess.check_output(["kubectl", "--context", "homelab", "-n", NS, *args], input=payload, text=True)


def resource(kind, name, spec, api="v1"):
    return {"apiVersion": api, "kind": kind, "metadata": {"name": name, "namespace": NS, "labels": {"trusted-ip-test": NAME}}, "spec": spec}


def connection(ip=IP):
    sock = socket.create_connection(("192.168.90.92", 8443), timeout=35)
    ipv6 = ":" in ip
    family = socket.AF_INET6 if ipv6 else socket.AF_INET
    addresses = socket.inet_pton(family, ip) + socket.inet_pton(family, "2001:db8::1" if ipv6 else "192.168.90.92") + struct.pack("!HH", 42000, 8443)
    sock.sendall(b"\r\n\r\n\x00\r\nQUIT\n" + bytes([0x21, 0x21 if ipv6 else 0x11]) + struct.pack("!H", len(addresses)) + addresses)
    conn = http.client.HTTPSConnection(HOST, timeout=35)
    conn.sock = ssl.create_default_context().wrap_socket(sock, server_hostname=HOST)
    return conn


def get(conn, path="/a", spoof=False):
    conn.request("GET", path, headers={"X-Homelab-Rate-Tier": "trusted", "X-Forwarded-For": IP} if spoof else {})
    response = conn.getresponse()
    body = response.read()
    return response.status, body


def burst(count, ip, path="/a"):
    def worker(n):
        conn = connection(ip)
        try:
            return [get(conn, path, spoof=True)[0] for _ in range(n)]
        finally:
            conn.close()
    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
        results = list(pool.map(worker, [count // 8 + (i < count % 8) for i in range(8)]))
    return [status for batch in results for status in batch]


def trust(ip, ttl):
    kubectl("exec", "trusted-ip-store-0", "--", "valkey-cli", "SET", "trusted-ip:v1:" + ip, "1", "EX", str(ttl))


def main():
    image = json.loads(kubectl("get", "deploy", "trusted-ip", "-o", "json"))["spec"]["template"]["spec"]["containers"][0]["image"]
    rules = json.loads(subprocess.check_output(["nix", "eval", "--json", "--file", str(ROOT / "node/k8s/trusted-ip-rules.nix")]))
    code = '''from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import time
class Handler(BaseHTTPRequestHandler):
 protocol_version = "HTTP/1.1"
 def do_GET(self):
  if self.path.endswith("slow"): time.sleep(20)
  body = self.headers.get("x-homelab-rate-tier", "missing").encode()
  self.send_response(200); self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
 def log_message(self, *args): pass
ThreadingHTTPServer(("0.0.0.0", 8080), Handler).serve_forever()
'''
    refs = [{"group": "gateway.networking.k8s.io", "kind": "HTTPRoute", "name": NAME + suffix} for suffix in ("-a", "-b")]
    items = [
        resource("Pod", NAME, {"automountServiceAccountToken": False, "containers": [{"name": "probe", "image": image, "imagePullPolicy": "Never", "command": ["python", "-c", code]}]}),
        resource("Service", NAME, {"selector": {"trusted-ip-test": NAME}, "ports": [{"port": 80, "targetPort": 8080}]}),
        resource("Service", NAME + "-unavailable", {"selector": {"trusted-ip-test": NAME + "-absent"}, "ports": [{"port": 9001, "targetPort": 9001, "appProtocol": "kubernetes.io/h2c"}]}),
        resource("BackendTrafficPolicy", NAME, {"targetRefs": refs, "timeout": {"http": {"requestTimeout": "0s"}}, "rateLimit": {"type": "Global", "global": {"rules": rules}}}, "gateway.envoyproxy.io/v1alpha1"),
        resource("SecurityPolicy", NAME, {"targetRefs": refs, "extAuth": {"failOpen": False, "timeout": "2s", "grpc": {"backendRefs": [{"name": "trusted-ip", "port": 9001}]}}}, "gateway.envoyproxy.io/v1alpha1"),
    ]
    for suffix in ("a", "b"):
        items.append(resource("HTTPRoute", NAME + "-" + suffix, {"hostnames": [HOST], "parentRefs": [{"name": "external", "sectionName": "public-secure"}], "rules": [{"matches": [{"path": {"type": "PathPrefix", "value": "/" + suffix}}], "backendRefs": [{"name": NAME, "port": 80}]}]}, "gateway.networking.k8s.io/v1"))
    try:
        print(kubectl("apply", "-f", "-", payload=json.dumps({"apiVersion": "v1", "kind": "List", "items": items})), flush=True)
        kubectl("wait", "--for=condition=Ready", "pod/" + NAME, "--timeout=60s")
        for _ in range(30):
            conn = connection("198.18.10.99")
            try:
                status, body = get(conn)
                if status == 200 and body == b"default":
                    break
            finally:
                conn.close()
            time.sleep(1)
        else:
            raise AssertionError("Test route or ext_authz not ready")
        # Avoid crossing a fixed minute window while checking exact thresholds.
        if time.time() % 60 > 15:
            time.sleep(60 - time.time() % 60 + 0.1)
        started = time.time()
        statuses = burst(101, IP)
        assert statuses.count(200) == 100 and statuses.count(429) == 1, statuses
        print("PASS: ordinary IP 100/101; spoofed trusted header is overwritten", flush=True)
        trust(IP, 120)
        statuses = burst(1201, IP)
        assert statuses.count(200) == 1200 and statuses.count(429) == 1, {x: statuses.count(x) for x in set(statuses)}
        assert int(started // 60) == int(time.time() // 60), "Crossed rate window; rerun"
        print("PASS: trusted IP 1200/1201, no overlapping base limit", flush=True)
        conn = connection(IP)
        assert get(conn, "/b") == (200, b"trusted")
        conn.close()
        conn = connection(OTHER_IP)
        assert get(conn, spoof=True) == (200, b"default")
        conn.close()
        print("PASS: independent routes and IPs; X-Forwarded-For cannot grant trust", flush=True)
        trust(IP6, 120)
        conn = connection(IP6)
        assert get(conn, "/b") == (200, b"trusted")
        conn.close()
        statuses = burst(101, "2001:db8:100::11")
        assert statuses.count(200) == 100 and statuses.count(429) == 1
        print("PASS: PROXY-protocol IPv6 identity and IPv6 rate limit", flush=True)
        trust(OTHER_IP, 2)
        conn = connection(OTHER_IP)
        assert get(conn, "/b") == (200, b"trusted")
        time.sleep(2.1)
        assert get(conn, "/b") == (200, b"default")
        conn.close()
        print("PASS: expiry restores base class without application traffic renewal", flush=True)
        conn = connection("198.18.10.12")
        started = time.monotonic()
        assert get(conn, "/b/slow") == (200, b"default")
        assert time.monotonic() - started >= 20
        conn.close()
        print("PASS: response lasting 20s is not interrupted", flush=True)
        policy = next(item for item in items if item["kind"] == "SecurityPolicy")
        policy["spec"]["extAuth"]["grpc"]["backendRefs"][0]["name"] = NAME + "-unavailable"
        kubectl("apply", "-f", "-", payload=json.dumps(policy))
        for _ in range(20):
            conn = connection("198.18.10.13")
            status, _ = get(conn, "/b", spoof=True)
            conn.close()
            if 500 <= status < 600:
                break
            time.sleep(1)
        else:
            raise AssertionError("Unavailable classifier did not fail closed")
        print("PASS: classifier outage returns 5xx even with spoofed trusted header", flush=True)
    finally:
        kubectl("exec", "trusted-ip-store-0", "--", "valkey-cli", "DEL", *["trusted-ip:v1:" + ip for ip in (IP, OTHER_IP, IP6)])
        print(kubectl("delete", "pod,service,httproute,backendtrafficpolicy,securitypolicy", "-l", "trusted-ip-test=" + NAME, "--wait=false"), flush=True)


if __name__ == "__main__":
    main()
