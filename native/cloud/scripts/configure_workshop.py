"""User-run private credential entry. Never pass secrets as command arguments."""
import argparse
import configparser
import getpass
import os
import shlex
import sys
import termios
from pathlib import Path

import boto3
from botocore.exceptions import BotoCoreError, ClientError


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--directory", type=Path, required=True)
    parser.add_argument("--expected-account", default="928489693154")
    parser.add_argument("--pasted-exports", action="store_true",
                        help="Read copied workshop export commands in a hidden terminal; never execute them")
    args = parser.parse_args()
    root = args.directory.expanduser().resolve()
    checkout = Path(__file__).resolve().parents[2]
    if root == checkout or checkout in root.parents:
        raise SystemExit("Choose a private runtime directory outside the repository.")
    print("Open Workshop Studio → AWS account access → Get AWS CLI credentials.")
    print("Paste ONLY each value below in this terminal. Input is hidden. Do not paste into chat.")
    if args.pasted_exports:
        if not sys.stdin.isatty():
            raise SystemExit("Private paste mode requires an interactive terminal.")
        before = termios.tcgetattr(sys.stdin.fileno())
        hidden = before.copy()
        hidden[3] &= ~termios.ECHO
        values = {}
        print("PRIVATE INPUT: paste the workshop export block, then type END on its own line.", flush=True)
        termios.tcsetattr(sys.stdin.fileno(), termios.TCSANOW, hidden)
        try:
            lines = []
            for line in sys.stdin:
                if line.strip() == "END":
                    break
                lines.append(line)
                if sum(map(len, lines)) > 32000:
                    raise SystemExit("Input too large. Nothing saved.")
            for line in lines:
                words = shlex.split(line.strip())
                if words and words[0] == "export":
                    words = words[1:]
                for word in words:
                    if "=" in word:
                        key, value = word.split("=", 1)
                        if key in {"AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"}:
                            values[key] = value
        finally:
            termios.tcsetattr(sys.stdin.fileno(), termios.TCSANOW, before)
        access, secret, token = (values.get(k, "") for k in
                                 ("AWS_ACCESS_KEY_ID", "AWS_SECRET_ACCESS_KEY", "AWS_SESSION_TOKEN"))
    else:
        access = getpass.getpass("AWS access key ID: ").strip().strip("\"'")
        secret = getpass.getpass("AWS secret access key: ").strip().strip("\"'")
        token = getpass.getpass("AWS session token: ").strip().strip("\"'")
    if not all([access, secret, token]) or any("\n" in s for s in (access, secret, token)):
        raise SystemExit("Expected three nonempty single-line values. Nothing saved.")
    session = boto3.Session(aws_access_key_id=access, aws_secret_access_key=secret,
                            aws_session_token=token, region_name="us-east-1")
    try:
        identity = session.client("sts").get_caller_identity()
    except (BotoCoreError, ClientError):
        raise SystemExit("AWS identity check failed. Nothing saved; refresh workshop credentials and retry.") from None
    if identity["Account"] != args.expected_account:
        raise SystemExit("Wrong AWS account. Nothing saved.")
    root.mkdir(parents=True, exist_ok=True, mode=0o700)
    os.chmod(root, 0o700)
    config = configparser.ConfigParser()
    config["relay-workshop"] = {"aws_access_key_id": access,
                                 "aws_secret_access_key": secret,
                                 "aws_session_token": token}
    path = root / "credentials"
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        config.write(f)
    os.chmod(path, 0o600)
    print("Verified account:", identity["Account"])
    print("Verified caller:", identity["Arn"])
    print("Saved temporary credentials privately; no credential values were printed.")
    print("Credential file:", path)


if __name__ == "__main__":
    main()
