## Trusted IP rate limits

Envoy's external HTTPS listener calls the Python gRPC `Authorization/Check`
service before rate limiting. The service always overwrites
`x-homelab-rate-tier`; it does not authenticate users to applications.
Only Envoy's connection address (including FRP PROXY protocol) identifies the
client. Client-supplied forwarded headers cannot grant trust.

An HTTPS request to the host configured by the required `AUTH_HOST` environment
variable (`auth.iverian.ru` in `node/k8s/trusted-ip.nix`, alongside the other
service addresses) with a valid two-factor Authelia session
refreshes that IP's Valkey record for 24 hours. The service checks only the
session cookie, against an internal, cookie-only Authelia authorization endpoint
and a fixed two-factor resource. Cookies, tokens and usernames are never stored
in Valkey or logged. Other hosts only read the record. All clients behind the
same IP share its classification. Logout does not revoke the record; moving to
another IP requires another visit to Authelia from that IP.

Ordinary clients get 100 requests/minute/IP/route; trusted clients get 1200.
IPv4 and IPv6 have separate matching rules. Nextcloud and CouchDB merge their
one-hour timeout policies with the external limit. Jellyfin merges a disabled
overall response timeout. The internal `main` Gateway has no external rate limit.

## Build and deploy

- `just trusted-ip-test`: build the pinned dependency image and run unit/gRPC tests.
- `just trusted-ip-image`: also import the image into the single node's containerd.
- `nix flake check`, `just plan`, `just apply`: normal deployment; apply imports
  the image before switching the NixOS configuration.
- `just trusted-ip-integration`: create temporary external routes and a synthetic
  backend, test IPv4/IPv6 limits, spoofing, TTL, a 20-second response and classifier
  failure, then remove the resources and benchmark-address trust records.

The image tag hashes Dockerfile and requirements; application code is mounted
from a ConfigMap with a rollout checksum. Python packages come from pinned wheels;
no application/protobuf compilation or external image registry is required.
The image must be imported on every schedulable node if this becomes a multi-node
cluster. The current deployment is designed for the existing single node.

Never run Nix with a decrypted `main.sops.yaml`: source files can enter the store.
The `just` rebuild workflow checks that SOPS metadata and encrypted values exist.
This guard does not validate every value or protect direct Nix invocations.

## Verification and failure behavior

Use local `kubectl --context homelab`. Check both replicas, Valkey, Authelia,
SecurityPolicy/BackendTrafficPolicy acceptance, k3s AddOns, and Envoy's actual
route configuration. A successful `nixos-rebuild` is not sufficient.

An Authelia error does not refresh trust; an unexpired record still applies.
A Valkey error returns the ordinary class, without retrying past the gRPC deadline.
Classifier unavailability fails closed with 5xx. Two replicas allow rolling
updates but do not provide node-level redundancy on a single-node cluster.

Prometheus metrics on port 9090 count classifications, Authelia verification
results and store errors. Labels never contain IPs or user identities. gRPC health
checks indicate process readiness, independent of dependency availability.

For end-to-end acceptance, visit Authelia through the external connection, finish
two-factor login, then access it once more with the established session. Confirm
the `verified` counter increases and the trust record TTL is close to 86400
without displaying cookies or tokens. Test a real Jellyfin download/playback
from another device behind the same IP. Synthetic tests do not prove this user flow.

## Rollback

Set `homelab.trustedIP.enforce = false` in `node/k8s/ingress.nix`, then run
`nix flake check`, `just plan`, and `just apply`. After activation remove the
retired policy with local
`kubectl --context homelab -n envoy-gateway-system delete securitypolicy trusted-ip`.
k3s does not delete live resources when a manifest disappears. Verify that the
retired manifest is absent from the node before deleting the resource.

This restores the gateway's ordinary 100/minute rule and removes the classifier
dependency. To reproduce the original Nextcloud/CouchDB exemptions, also remove
their `mergeType` fields. Keep Jellyfin's streaming timeout fix. Leave the idle
service and store deployed until the rollback is verified; remove them separately
with explicit resource cleanup if no longer needed.

## Deployment verification, 2026-11-09

- Nix flake evaluation and dry activation passed on the deployment snapshot;
  both staged and final activations completed successfully.
- All 11 Python tests passed in the deployment image. Live temporary-route tests
  passed for both rate tiers, IPv4/IPv6, spoofing, independent counters, expiry,
  a 20-second response, and classifier unavailability returning 5xx.
- Actual Envoy configuration shows Jellyfin `0s`, Nextcloud/CouchDB `3600s`,
  external classification before rate limiting, and no limits on `main`.
- The user confirmed Jellyfin works after external Authelia login. The service
  recorded successful verification and a real trust entry with approximately
  24 hours remaining; no store errors were reported. A full large-file download
  was not independently measured.
- All workloads were Ready. One transient IPAddress warning during creation of
  the Valkey Service resolved: the stale address was removed and current
  endpoints are Ready. Authelia still reports the pre-existing unsupported
  `AUTHELIA_TRUSTED_PROXIES_0` environment setting.
- A concurrent decrypted working secret file was excluded from final deployment:
  the original encrypted version was used in an isolated snapshot. Accidental
  plaintext Nix-store copies from the failed dry run were removed locally and on
  the node. The user's working secret file was left untouched.
