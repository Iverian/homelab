## Local service images

Every locally built service lives directly under `services/` and may provide a
minimal `manifest.json`:

```json
{
  "image": "localhost/homelab/example",
  "hashFiles": [
    "requirements.txt"
  ]
}
```

`image` is an untagged repository name. `hashFiles` contains paths relative to
the service directory, in hash order. The selected Dockerfile is always the
first hash input and must not be listed. The first 20 hexadecimal characters of
the SHA-256 digest become the image tag. Paths outside the service directory,
unknown manifest fields and tagged image names are rejected.

Build and import every manifest into the default node:

```bash
just service-images
```

Build everything locally without contacting the node:

```bash
just service-images homelab --no-upload
```

Build one image:

```bash
just service-image services/homepage/manifest.json
```

The generic script also accepts `--platform`, `--dockerfile`, repeated
`--build-arg`, `--pull`, `--no-cache`, node/SSH options and optional `docker
run` settings. Run `python3 script/service_images.py --help` for the complete
interface. Arguments after `--` are passed to the container when `--run` is
set.

The same manifest must be read by the Nix module that references the image, so
the deployment and builder derive exactly the same repository and tag.
