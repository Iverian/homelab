"""Classify Envoy requests; application authentication remains with the backend."""

import asyncio
import ipaddress
import logging
import os
import signal
from http.cookies import CookieError, SimpleCookie

import grpc
import httpx
from envoy.config.core.v3 import base_pb2
from envoy.service.auth.v3 import external_auth_pb2 as auth_pb2
from envoy.service.auth.v3 import external_auth_pb2_grpc as auth_grpc
from google.rpc import code_pb2, status_pb2
from grpc_health.v1 import health, health_pb2, health_pb2_grpc
from prometheus_client import Counter, start_http_server
from redis.asyncio import Redis
from redis.asyncio.retry import Retry
from redis.backoff import NoBackoff
from redis.exceptions import RedisError

TIER_HEADER = "x-homelab-rate-tier"
KEY_PREFIX = "trusted-ip:v1:"
TTL_SECONDS = 86400
AUTH_HOST = os.environ["AUTH_HOST"].lower()
CHECK_URL = f"https://{AUTH_HOST}/_trusted-ip-check"
REQUESTS = Counter("trusted_ip_checks_total", "Classification results", ["tier"])
VERIFICATIONS = Counter("trusted_ip_verifications_total", "Authelia checks", ["result"])
STORE_ERRORS = Counter("trusted_ip_store_errors_total", "Trust store failures")


def normalize_ip(value):
    # Zone IDs are neither stable identities nor valid public client addresses.
    if "%" in value:
        raise ValueError("scoped address")
    address = ipaddress.ip_address(value)
    if isinstance(address, ipaddress.IPv6Address) and address.ipv4_mapped:
        address = address.ipv4_mapped
    return str(address)


def session_cookie(headers):
    raw = headers.get("cookie", "")
    if len(raw) > 16384:
        return None
    # Reject duplicate session cookies instead of choosing a possibly different
    # value from Authelia. Forward no unrelated application cookies.
    if sum(part.strip().startswith("authelia_session=") for part in raw.split(";")) != 1:
        return None
    cookies = SimpleCookie()
    try:
        cookies.load(raw)
    except CookieError:
        return None
    cookie = cookies.get("authelia_session")
    return cookie.OutputString() if cookie and cookie.value else None


class Classifier(auth_grpc.AuthorizationServicer):
    def __init__(self, store, client, auth_url):
        self.store = store
        self.client = client
        self.auth_url = auth_url

    async def verify(self, cookie, ip):
        try:
            response = await self.client.get(
                self.auth_url,
                headers={
                    "Cookie": cookie,
                    "X-Forwarded-Method": "GET",
                    "X-Forwarded-Proto": "https",
                    "X-Forwarded-Host": AUTH_HOST,
                    "X-Forwarded-Uri": "/_trusted-ip-check",
                    "X-Original-URL": CHECK_URL,
                    "X-Forwarded-For": ip,
                },
            )
        except httpx.HTTPError:
            VERIFICATIONS.labels("error").inc()
            return False
        valid = response.status_code == 200 and bool(response.headers.get("Remote-User", "").strip())
        VERIFICATIONS.labels("verified" if valid else "denied").inc()
        return valid

    async def classify(self, request):
        try:
            ip = normalize_ip(request.attributes.source.address.socket_address.address)
        except ValueError:
            return "default"
        http = request.attributes.request.http
        cookie = session_cookie(http.headers) if http.host.lower() in (AUTH_HOST, AUTH_HOST + ":443") and http.scheme == "https" else None
        verified = bool(cookie) and await self.verify(cookie, ip)
        try:
            if verified:
                # A failed write never grants elevated access, even for this request.
                await self.store.set(KEY_PREFIX + ip, "1", ex=TTL_SECONDS)
                return "trusted"
            return "trusted" if await self.store.get(KEY_PREFIX + ip) == b"1" else "default"
        except (RedisError, OSError, TimeoutError):
            STORE_ERRORS.inc()
            return "default"

    async def Check(self, request, context):
        tier = await self.classify(request)
        REQUESTS.labels(tier).inc()
        return auth_pb2.CheckResponse(
            status=status_pb2.Status(code=code_pb2.OK),
            ok_response=auth_pb2.OkHttpResponse(headers=[
                base_pb2.HeaderValueOption(
                    header=base_pb2.HeaderValue(key=TIER_HEADER, value=tier),
                    append_action=base_pb2.HeaderValueOption.OVERWRITE_IF_EXISTS_OR_ADD,
                )
            ]),
        )


async def main():
    logging.basicConfig(level=logging.WARNING)
    store = Redis.from_url(
        os.environ["REDIS_URL"], socket_connect_timeout=0.2,
        socket_timeout=0.2, retry=Retry(NoBackoff(), 0), max_connections=128,
    )
    async with httpx.AsyncClient(timeout=0.75, follow_redirects=False, trust_env=False) as client:
        server = grpc.aio.server(options=[("grpc.max_receive_message_length", 65536)], maximum_concurrent_rpcs=256)
        auth_grpc.add_AuthorizationServicer_to_server(Classifier(store, client, os.environ["AUTHELIA_AUTHZ_URL"]), server)
        health_service = health.aio.HealthServicer()
        health_pb2_grpc.add_HealthServicer_to_server(health_service, server)
        await health_service.set("", health_pb2.HealthCheckResponse.SERVING)
        server.add_insecure_port("[::]:9001")
        start_http_server(9090)
        await server.start()
        stop = asyncio.Event()
        for sig in (signal.SIGINT, signal.SIGTERM):
            asyncio.get_running_loop().add_signal_handler(sig, stop.set)
        await stop.wait()
        await health_service.enter_graceful_shutdown()
        await server.stop(5)
    await store.aclose()


if __name__ == "__main__":
    asyncio.run(main())
