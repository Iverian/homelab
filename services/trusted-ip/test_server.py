import unittest
from unittest.mock import AsyncMock

import grpc
import httpx
from envoy.service.auth.v3 import external_auth_pb2 as auth_pb2
from envoy.service.auth.v3 import external_auth_pb2_grpc as auth_grpc
from redis.exceptions import ConnectionError

from server import AUTH_HOST, Classifier, KEY_PREFIX, TIER_HEADER, TTL_SECONDS, normalize_ip


def request(ip="203.0.113.10", host=AUTH_HOST, cookie="authelia_session=test-session"):
    req = auth_pb2.CheckRequest()
    req.attributes.source.address.socket_address.address = ip
    req.attributes.request.http.host = host
    req.attributes.request.http.scheme = "https"
    req.attributes.request.http.headers.update({"cookie": cookie, TIER_HEADER: "trusted", "x-forwarded-for": "198.51.100.8"})
    return req


class Store:
    def __init__(self):
        self.now = 0
        self.entries = {}

    async def set(self, key, value, ex):
        self.entries[key] = (value.encode(), self.now + ex)

    async def get(self, key):
        value, expiry = self.entries.get(key, (None, 0))
        return value if expiry > self.now else None


class Tests(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        self.store = Store()
        self.response = httpx.Response(200, headers={"Remote-User": "test-user"})
        self.http = httpx.AsyncClient(transport=httpx.MockTransport(lambda _: self.response))
        self.classifier = Classifier(self.store, self.http, "http://authelia/api/authz/trusted-ip")

    async def asyncTearDown(self):
        await self.http.aclose()

    async def test_activation_other_devices_and_expiry(self):
        self.assertEqual(await self.classifier.classify(request()), "trusted")
        self.store.now = TTL_SECONDS - 1
        self.assertEqual(await self.classifier.classify(request(host="jellyfin.iverian.ru", cookie="")), "trusted")
        self.assertEqual(await self.classifier.classify(request(ip="203.0.113.11", host="jellyfin.iverian.ru")), "default")
        self.store.now += 1
        self.assertEqual(await self.classifier.classify(request(host="jellyfin.iverian.ru")), "default")

    async def test_only_successful_auth_check_renews(self):
        await self.classifier.classify(request())
        self.store.now = 100
        await self.classifier.classify(request())
        self.assertEqual(self.store.entries[KEY_PREFIX + "203.0.113.10"][1], TTL_SECONDS + 100)
        self.response = httpx.Response(401)
        self.store.now = 200
        self.assertEqual(await self.classifier.classify(request()), "trusted")
        self.assertEqual(self.store.entries[KEY_PREFIX + "203.0.113.10"][1], TTL_SECONDS + 100)

    async def test_invalid_auth_never_creates_trust(self):
        for status, headers in [(200, {}), (200, {"Remote-User": " "}), (302, {"Location": f"https://{AUTH_HOST}"}), (401, {}), (403, {}), (500, {})]:
            self.response = httpx.Response(status, headers=headers)
            self.assertEqual(await self.classifier.classify(request()), "default")
        self.assertFalse(self.store.entries)

    async def test_auth_outage_preserves_unexpired_trust(self):
        await self.classifier.classify(request())
        self.classifier.client = AsyncMock()
        self.classifier.client.get.side_effect = httpx.ConnectError("unavailable")
        self.store.now = 100
        self.assertEqual(await self.classifier.classify(request()), "trusted")
        self.assertEqual(self.store.entries[KEY_PREFIX + "203.0.113.10"][1], TTL_SECONDS)
        self.assertEqual(await self.classifier.classify(request(ip="203.0.113.12")), "default")

    async def test_store_read_and_write_failure_downgrades(self):
        self.classifier.store = AsyncMock()
        self.classifier.store.get.side_effect = ConnectionError()
        self.classifier.store.set.side_effect = ConnectionError()
        self.assertEqual(await self.classifier.classify(request()), "default")
        self.assertEqual(await self.classifier.classify(request(cookie="")), "default")

    async def test_forwarded_headers_do_not_select_identity(self):
        await self.store.set(KEY_PREFIX + "198.51.100.8", "1", ex=TTL_SECONDS)
        result = await self.classifier.Check(request(cookie=""), None)
        header = result.ok_response.headers[0]
        self.assertEqual(header.header.value, "default")
        self.assertEqual(header.append_action, header.OVERWRITE_IF_EXISTS_OR_ADD)

    async def test_only_auth_host_and_https_can_activate(self):
        for host in ["jellyfin.example.test", AUTH_HOST + ".evil", AUTH_HOST + ":444"]:
            self.assertEqual(await self.classifier.classify(request(host=host)), "default")
        req = request()
        req.attributes.request.http.scheme = "http"
        self.assertEqual(await self.classifier.classify(req), "default")

    async def test_missing_malformed_duplicate_cookies(self):
        for cookie in ["", "other=value", "authelia_session=", "authelia_session=a; authelia_session=b", "x" * 16385]:
            self.assertEqual(await self.classifier.classify(request(cookie=cookie)), "default")

    async def test_only_session_cookie_forwarded_and_no_client_auth_headers(self):
        self.classifier.client = AsyncMock()
        self.classifier.client.get.return_value = self.response
        await self.classifier.classify(request(cookie="other=secret; authelia_session=session"))
        forwarded = self.classifier.client.get.call_args.kwargs["headers"]
        self.assertEqual(forwarded["Cookie"], "authelia_session=session")
        self.assertEqual(forwarded["X-Forwarded-For"], "203.0.113.10")
        self.assertEqual(forwarded["X-Forwarded-Host"], AUTH_HOST)
        self.assertEqual(forwarded["X-Original-URL"], f"https://{AUTH_HOST}/_trusted-ip-check")
        self.assertNotIn("Authorization", forwarded)

    async def test_ip_normalization(self):
        self.assertEqual(normalize_ip("::ffff:203.0.113.10"), "203.0.113.10")
        self.assertEqual(normalize_ip("2001:db8:0:0::1"), "2001:db8::1")
        for ip in ["", "bad", "fe80::1%eth0"]:
            self.assertEqual(await self.classifier.classify(request(ip=ip)), "default")

    async def test_grpc_wire_roundtrip(self):
        server = grpc.aio.server()
        auth_grpc.add_AuthorizationServicer_to_server(self.classifier, server)
        port = server.add_insecure_port("127.0.0.1:0")
        await server.start()
        try:
            async with grpc.aio.insecure_channel(f"127.0.0.1:{port}") as channel:
                result = await auth_grpc.AuthorizationStub(channel).Check(request(), timeout=2)
                self.assertEqual(result.status.code, 0)
                self.assertEqual(result.ok_response.headers[0].header.value, "trusted")
        finally:
            await server.stop(0)


if __name__ == "__main__":
    unittest.main()
