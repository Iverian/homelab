"""Build a content-addressed dependency image and import it into this single node."""
import hashlib
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parent.parent
context = root / "services/trusted-ip"
tag = hashlib.sha256((context / "Dockerfile").read_bytes() + (context / "requirements.txt").read_bytes()).hexdigest()[:20]
image = f"localhost/homelab/trusted-ip:{tag}"
subprocess.run(["docker", "build", "--platform", "linux/amd64", "-t", image, str(context)], check=True)
subprocess.run(["docker", "run", "--rm", "--network", "none", "-e", "AUTH_HOST=auth.example.test", "-v", f"{context}:/app:ro", image, "python", "-m", "unittest", "-v"], check=True)
if len(sys.argv) > 1 and sys.argv[1] == "--test-only":
    sys.exit(0)
node = sys.argv[1] if len(sys.argv) > 1 else "homelab"
if not node.replace("-", "").isalnum():
    raise SystemExit("Invalid node name")
host = f"iverian@{node}.lan"
available = subprocess.check_output(["ssh", host, "sudo k3s ctr images list -q"], text=True).splitlines()
if image not in available:
    producer = subprocess.Popen(["docker", "save", image], stdout=subprocess.PIPE)
    try:
        subprocess.run(["ssh", host, "sudo k3s ctr images import -"], stdin=producer.stdout, check=True)
    finally:
        producer.stdout.close()
    if producer.wait() != 0:
        raise SystemExit("docker save failed")
print(f"Dependency image ready: {image}")
