"""Build content-addressed service images and import them into a k3s node."""

from __future__ import annotations

import argparse
from dataclasses import dataclass
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
from typing import Sequence


ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SERVICES_DIR = ROOT / "services"
MANIFEST_KEYS = {"image", "hashFiles"}
IMAGE_RE = re.compile(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*(?::[0-9]+)?(?:/[a-z0-9]+(?:[._-][a-z0-9]+)*)+$")
SSH_HOST_RE = re.compile(r"^[A-Za-z0-9_.@-]+$")


@dataclass(frozen=True)
class ImageSpec:
    manifest: Path
    context: Path
    dockerfile: Path
    repository: str
    hash_files: tuple[Path, ...]
    tag: str

    @property
    def image(self) -> str:
        return f"{self.repository}:{self.tag}"


def _relative_file(context: Path, value: str, field: str) -> Path:
    candidate = (context / value).resolve()
    try:
        candidate.relative_to(context)
    except ValueError as error:
        raise ValueError(f"{field} escapes service directory: {value}") from error
    if not candidate.is_file():
        raise ValueError(f"{field} is not a file: {value}")
    return candidate


def load_spec(manifest: Path, dockerfile_name: str = "Dockerfile") -> ImageSpec:
    manifest = manifest.resolve()
    if not manifest.is_file():
        raise ValueError(f"manifest does not exist: {manifest}")
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise ValueError(f"invalid JSON in {manifest}: {error}") from error
    if not isinstance(data, dict):
        raise ValueError(f"manifest must contain a JSON object: {manifest}")
    unknown = set(data) - MANIFEST_KEYS
    if unknown:
        raise ValueError(f"unsupported manifest keys in {manifest}: {', '.join(sorted(unknown))}")

    repository = data.get("image")
    if not isinstance(repository, str) or not IMAGE_RE.fullmatch(repository):
        raise ValueError(f"image must be an untagged lowercase repository name: {manifest}")
    values = data.get("hashFiles", [])
    if not isinstance(values, list) or not all(isinstance(value, str) and value for value in values):
        raise ValueError(f"hashFiles must be an array of non-empty strings: {manifest}")

    context = manifest.parent.resolve()
    dockerfile = _relative_file(context, dockerfile_name, "Dockerfile")
    files: list[Path] = [dockerfile]
    for value in values:
        path = _relative_file(context, value, "hashFiles entry")
        if path not in files:
            files.append(path)

    digest = hashlib.sha256()
    for path in files:
        digest.update(path.read_bytes())
    return ImageSpec(
        manifest=manifest,
        context=context,
        dockerfile=dockerfile,
        repository=repository,
        hash_files=tuple(files),
        tag=digest.hexdigest()[:20],
    )


def discover_manifests(services_dir: Path) -> list[Path]:
    manifests = sorted(services_dir.resolve().glob("*/manifest.json"))
    if not manifests:
        raise ValueError(f"no service manifests found under {services_dir}")
    return manifests


def build(spec: ImageSpec, args: argparse.Namespace) -> None:
    command = [
        "docker",
        "build",
        "--platform",
        args.platform,
        "--file",
        str(spec.dockerfile),
        "--tag",
        spec.image,
    ]
    if args.pull:
        command.append("--pull")
    if args.no_cache:
        command.append("--no-cache")
    for value in args.build_arg:
        command.extend(["--build-arg", value])
    command.append(str(spec.context))
    subprocess.run(command, check=True)


def _volume(value: str, context: Path) -> str:
    parts = value.split(":", 2)
    if len(parts) < 2:
        raise ValueError(f"run volume must be HOST:CONTAINER[:MODE]: {value}")
    host_path = Path(parts[0])
    if not host_path.is_absolute():
        host_path = (context / host_path).resolve()
    parts[0] = str(host_path)
    return ":".join(parts)


def run_image(spec: ImageSpec, args: argparse.Namespace, container_command: Sequence[str]) -> None:
    command = ["docker", "run", "--rm"]
    if args.run_network:
        command.extend(["--network", args.run_network])
    for value in args.run_env:
        command.extend(["--env", value])
    for value in args.run_volume:
        command.extend(["--volume", _volume(value, spec.context)])
    for value in args.run_arg:
        command.append(value)
    command.append(spec.image)
    command.extend(container_command)
    subprocess.run(command, check=True)


def ssh_host(args: argparse.Namespace) -> str:
    if args.host:
        host = args.host
    else:
        if not re.fullmatch(r"[A-Za-z0-9-]+", args.node):
            raise ValueError(f"invalid node name: {args.node}")
        host = f"{args.ssh_user}@{args.node}.{args.ssh_domain}"
    if host.startswith("-") or not SSH_HOST_RE.fullmatch(host):
        raise ValueError(f"invalid SSH host: {host}")
    return host


def upload(images: Sequence[str], host: str) -> None:
    available = set(
        subprocess.check_output(
            ["ssh", host, "sudo", "k3s", "ctr", "images", "list", "-q"],
            text=True,
        ).splitlines()
    )
    missing = [image for image in images if image not in available]
    if not missing:
        print("All images are already present on the node.")
        return

    producer = subprocess.Popen(["docker", "save", *missing], stdout=subprocess.PIPE)
    assert producer.stdout is not None
    try:
        importer = subprocess.run(
            ["ssh", host, "sudo", "k3s", "ctr", "images", "import", "-"],
            stdin=producer.stdout,
            check=False,
        )
    finally:
        producer.stdout.close()
    producer_status = producer.wait()
    if importer.returncode != 0:
        raise subprocess.CalledProcessError(importer.returncode, importer.args)
    if producer_status != 0:
        raise SystemExit("docker save failed")


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("manifests", nargs="*", type=Path, help="service manifest.json files")
    result.add_argument("--all", action="store_true", help="use every services/*/manifest.json")
    result.add_argument("--services-dir", type=Path, default=DEFAULT_SERVICES_DIR)
    result.add_argument("--dockerfile", default="Dockerfile", help="Dockerfile path relative to each service")
    result.add_argument("--platform", default="linux/amd64")
    result.add_argument("--build-arg", action="append", default=[])
    result.add_argument("--pull", action="store_true")
    result.add_argument("--no-cache", action="store_true")
    result.add_argument("--no-upload", action="store_true", help="build locally without importing into k3s")
    result.add_argument("--node", default="homelab")
    result.add_argument("--host", help="exact SSH destination; overrides node/user/domain")
    result.add_argument("--ssh-user", default="iverian")
    result.add_argument("--ssh-domain", default="lan")
    result.add_argument("--run", action="store_true", help="run each image after building it")
    result.add_argument("--run-network")
    result.add_argument("--run-env", action="append", default=[])
    result.add_argument("--run-volume", action="append", default=[])
    result.add_argument("--run-arg", action="append", default=[], help="raw docker run option")
    return result


def main(argv: Sequence[str] | None = None) -> int:
    values = list(sys.argv[1:] if argv is None else argv)
    if "--" in values:
        separator = values.index("--")
        option_values = values[:separator]
        container_command = values[separator + 1 :]
    else:
        option_values = values
        container_command = []
    args = parser().parse_args(option_values)

    if args.all == bool(args.manifests):
        raise SystemExit("select either --all or one or more manifest files")
    if container_command and not args.run:
        raise SystemExit("a command after -- requires --run")
    manifests = discover_manifests(args.services_dir) if args.all else args.manifests

    try:
        specs = [load_spec(path, args.dockerfile) for path in manifests]
        images = [spec.image for spec in specs]
        if len(images) != len(set(images)):
            raise ValueError("multiple manifests resolve to the same image tag")
        for spec in specs:
            print(f"Building {spec.image} from {spec.manifest}")
            build(spec, args)
            if args.run:
                run_image(spec, args, container_command)
        if not args.no_upload:
            host = ssh_host(args)
            upload(images, host)
        for image in images:
            print(f"Service image ready: {image}")
    except ValueError as error:
        raise SystemExit(str(error)) from error
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
