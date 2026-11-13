## Converse image

The image contains the pinned Converse.js distribution and an unprivileged,
Debian/glibc-based nginx. Runtime configuration and the private URL path remain
in the SOPS-rendered Kubernetes resources; they are not embedded in the image.

`manifest.json` contains only the image repository and additional hash inputs.
Dockerfile is included in the content-derived tag automatically.

Build and import this image with:

```bash
just service-image services/converse/manifest.json
```

Build and import all locally maintained service images with:

```bash
just service-images
```
