"""Create isolated local-test keys/config. These identities never authenticate to AWS."""
import argparse
import json
import os
import time
from pathlib import Path

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import rsa


def bootstrap(root: Path, port=8787):
    root = root.resolve()
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(root, 0o700)
    private_path, public_path = root / "test-signing-key.pem", root / "test-public-key.pem"
    if not private_path.exists():
        key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
        private_path.write_bytes(key.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                                  serialization.NoEncryption()))
        private_path.chmod(0o600)
        public_path.write_bytes(key.public_key().public_bytes(serialization.Encoding.PEM,
                                                             serialization.PublicFormat.SubjectPublicKeyInfo))
    key = serialization.load_pem_private_key(private_path.read_bytes(), password=None)
    members = {"test-requester-a": {"role": "requester", "incident_id": "synthetic-demo-01", "shelter_ids": ["shelter-a"]},
               "test-requester-b": {"role": "requester", "incident_id": "synthetic-demo-01", "shelter_ids": ["shelter-b"]},
               "test-dispatcher-a": {"role": "dispatcher", "incident_id": "synthetic-demo-01", "shelter_ids": ["shelter-a"]},
               "test-dispatcher-b": {"role": "dispatcher", "incident_id": "synthetic-demo-01", "shelter_ids": ["shelter-b"]}}
    config = {"mode": "local-test", "storage": "sqlite", "runtime_dir": str(root),
              "public_base_url": f"http://127.0.0.1:{port}", "local_public_key": str(public_path),
              "memberships": members,
              "shelters": [{"shelter_id": "shelter-a", "incident_id": "synthetic-demo-01", "display_name": "Shelter A"},
                           {"shelter_id": "shelter-b", "incident_id": "synthetic-demo-01", "display_name": "Shelter B"}]}
    config_path = root / "local-config.json"
    config_path.write_text(json.dumps(config, indent=2) + "\n")
    tokens = {name: jwt.encode({"iss": "http://relay.local-test", "sub": name, "client_id": "relay-local-test",
                               "token_use": "access", "iat": int(time.time()), "exp": int(time.time()) + 3600},
                              key, algorithm="RS256", headers={"kid": "local-test-only"}) for name in members}
    token_path = root / "local-test-tokens.json"
    token_path.write_text(json.dumps(tokens))
    token_path.chmod(0o600)
    return config_path, token_path


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-dir", type=Path, required=True)
    parser.add_argument("--port", type=int, default=8787)
    args = parser.parse_args()
    checkout = Path(__file__).resolve().parents[2]
    if checkout == args.runtime_dir.resolve() or checkout in args.runtime_dir.resolve().parents:
        raise SystemExit("Use a runtime directory outside the repository.")
    config, tokens = bootstrap(args.runtime_dir, args.port)
    print("LOCAL TEST ONLY; no AWS authentication or inference.")
    print("Config:", config)
    print("Private one-hour test token file:", tokens)
