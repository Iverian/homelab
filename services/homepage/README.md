## Homepage image

Homepage v2.8.0 is built from its checksum-pinned source archive. Both build
and runtime stages use Debian/glibc images; the upstream Alpine runtime image
is intentionally not used.

Build locally without uploading it to the node:

```bash
just service-image services/homepage/manifest.json homelab --no-upload
```
