#!/usr/bin/env python3
"""Safely refresh a dnscrypt-proxy domain blocklist."""

from __future__ import annotations

import argparse
import hashlib
import os
from pathlib import Path
import re
import tempfile
import urllib.request


DOMAIN_RE = re.compile(
    r"(?=.{1,253}\Z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+"
    r"[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\Z"
)
MAX_DOWNLOAD_BYTES = 32 * 1024 * 1024


def download(url: str, timeout: int) -> bytes:
    if not url.startswith("https://"):
        raise ValueError("blocklist URL must use HTTPS")
    request = urllib.request.Request(url, headers={"User-Agent": "homelab-dns-blocklist-updater/1"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        content_length = response.headers.get("Content-Length")
        if content_length is not None and int(content_length) > MAX_DOWNLOAD_BYTES:
            raise ValueError("blocklist is larger than the download limit")
        payload = response.read(MAX_DOWNLOAD_BYTES + 1)
    if len(payload) > MAX_DOWNLOAD_BYTES:
        raise ValueError("blocklist is larger than the download limit")
    return payload


def normalize(payload: bytes, minimum_entries: int) -> bytes:
    text = payload.decode("utf-8")
    domains: set[str] = set()
    for line_number, raw_line in enumerate(text.splitlines(), 1):
        line = raw_line.strip().lower()
        if not line or line.startswith("#"):
            continue
        if not DOMAIN_RE.fullmatch(line):
            raise ValueError(f"invalid domain on source line {line_number}")
        domains.add(line)
    if len(domains) < minimum_entries:
        raise ValueError(
            f"blocklist has only {len(domains)} entries; expected at least {minimum_entries}"
        )
    return ("\n".join(sorted(domains)) + "\n").encode("ascii")


def replace_if_changed(target: Path, content: bytes) -> bool:
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.exists() and target.read_bytes() == content:
        return False

    file_descriptor, temporary_name = tempfile.mkstemp(
        dir=target.parent, prefix=f".{target.name}.", suffix=".tmp"
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(file_descriptor, "wb") as stream:
            stream.write(content)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.chmod(0o644)
        os.replace(temporary, target)
    finally:
        temporary.unlink(missing_ok=True)
    return True


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", required=True)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--minimum-entries", type=int, default=50_000)
    parser.add_argument("--timeout", type=int, default=60)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    content = normalize(download(args.url, args.timeout), args.minimum_entries)
    changed = replace_if_changed(args.output, content)
    digest = hashlib.sha256(content).hexdigest()
    entries = len(content.splitlines())
    action = "updated" if changed else "unchanged"
    print(f"Blocklist {action}: entries={entries} sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
