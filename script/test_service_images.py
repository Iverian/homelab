import hashlib
import json
from pathlib import Path
import tempfile
import unittest

import service_images


class ImageManifestTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.service = self.root / "services" / "example"
        self.service.mkdir(parents=True)
        (self.service / "Dockerfile").write_text("FROM scratch\n", encoding="utf-8")
        (self.service / "requirements.txt").write_text("example==1\n", encoding="utf-8")

    def tearDown(self):
        self.temporary.cleanup()

    def manifest(self, data):
        path = self.service / "manifest.json"
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def test_dockerfile_is_hashed_by_default(self):
        manifest = self.manifest({"image": "localhost/homelab/example", "hashFiles": []})
        spec = service_images.load_spec(manifest)
        expected = hashlib.sha256((self.service / "Dockerfile").read_bytes()).hexdigest()[:20]
        self.assertEqual(spec.tag, expected)
        self.assertEqual(spec.hash_files, (self.service / "Dockerfile",))

    def test_hash_files_follow_dockerfile_in_manifest_order(self):
        manifest = self.manifest(
            {"image": "localhost/homelab/example", "hashFiles": ["requirements.txt"]}
        )
        spec = service_images.load_spec(manifest)
        expected = hashlib.sha256(
            (self.service / "Dockerfile").read_bytes()
            + (self.service / "requirements.txt").read_bytes()
        ).hexdigest()[:20]
        self.assertEqual(spec.tag, expected)

    def test_paths_cannot_escape_service_directory(self):
        outside = self.root / "outside"
        outside.write_text("secret", encoding="utf-8")
        manifest = self.manifest(
            {"image": "localhost/homelab/example", "hashFiles": ["../../outside"]}
        )
        with self.assertRaisesRegex(ValueError, "escapes service directory"):
            service_images.load_spec(manifest)

    def test_unknown_manifest_keys_are_rejected(self):
        manifest = self.manifest(
            {"image": "localhost/homelab/example", "hashFiles": [], "platform": "linux/amd64"}
        )
        with self.assertRaisesRegex(ValueError, "unsupported manifest keys"):
            service_images.load_spec(manifest)

    def test_discovers_only_direct_service_manifests(self):
        self.manifest({"image": "localhost/homelab/example", "hashFiles": []})
        nested = self.service / "nested"
        nested.mkdir()
        (nested / "manifest.json").write_text("{}", encoding="utf-8")
        self.assertEqual(
            service_images.discover_manifests(self.root / "services"),
            [self.service / "manifest.json"],
        )


if __name__ == "__main__":
    unittest.main()
