"""Fail before invoking Nix when the working SOPS file is decrypted."""
from pathlib import Path

data = (Path(__file__).resolve().parent.parent / "main.sops.yaml").read_bytes()
if b"\nsops:" not in data or b"ENC[AES256_GCM," not in data:
    raise SystemExit("main.sops.yaml is not SOPS-encrypted. Encrypt it before running Nix deployment workflows.")
