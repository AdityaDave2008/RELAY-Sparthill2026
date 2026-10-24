"""Provision ONLY the approved isolated demo client/users. Existing MFA settings are preserved."""
import argparse
import base64
import hashlib
import hmac
import json
import os
import secrets
import struct
import time
from pathlib import Path

import boto3
from botocore.exceptions import ClientError

POOL = "us-east-1_f7wyKUgiY"
ACCOUNT = "928489693154"
CLIENT_NAME = "RELAY-Cloud-MVP-Native"
DOMAIN = "relay-mvp-928489693154"
CALLBACKS = ["relay://oauth/callback", "http://localhost:8400/callback"]
ACTORS = ["test-requester-a", "test-requester-b", "test-dispatcher-a", "test-dispatcher-b"]


def write_private(path, data):
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        json.dump(data, f, indent=2)
    os.chmod(path, 0o600)


def totp(secret):
    key = base64.b32decode(secret + "=" * (-len(secret) % 8), casefold=True)
    d = hmac.new(key, struct.pack(">Q", int(time.time()) // 30), hashlib.sha1).digest()
    offset = d[-1] & 15
    return f"{(struct.unpack('>I', d[offset:offset + 4])[0] & 0x7fffffff) % 1000000:06d}"


def authenticate(client, client_id, user, save_private):
    response = client.initiate_auth(ClientId=client_id, AuthFlow="USER_PASSWORD_AUTH",
                                    AuthParameters={"USERNAME": user["username"], "PASSWORD": user["password"]})
    initial_challenge = response.get("ChallengeName")
    challenge_user = response.get("ChallengeParameters", {}).get("USER_ID_FOR_SRP") or response.get("ChallengeParameters", {}).get("USERNAME") or user["username"]
    if response.get("ChallengeName") == "MFA_SETUP":
        enrolled = client.associate_software_token(Session=response["Session"])
        user["totp_secret"] = enrolled["SecretCode"]
        save_private()
        verified = client.verify_software_token(Session=enrolled["Session"], UserCode=totp(user["totp_secret"]),
                                                 FriendlyDeviceName="RELAY synthetic backend test")
        if verified.get("Status") != "SUCCESS":
            raise RuntimeError("Synthetic-user MFA setup failed")
        response = client.respond_to_auth_challenge(ClientId=client_id, ChallengeName="MFA_SETUP",
                                                     Session=verified["Session"],
                                                     ChallengeResponses={"USERNAME": challenge_user})
    if response.get("ChallengeName") == "SOFTWARE_TOKEN_MFA":
        if not user.get("totp_secret"):
            raise RuntimeError("Synthetic user's existing MFA secret is unavailable; no reset attempted")
        response = client.respond_to_auth_challenge(ClientId=client_id, ChallengeName="SOFTWARE_TOKEN_MFA",
                                                     Session=response["Session"], ChallengeResponses={
                                                         "USERNAME": challenge_user, "SOFTWARE_TOKEN_MFA_CODE": totp(user["totp_secret"])})
    if "AuthenticationResult" not in response:
        raise RuntimeError("Unexpected Cognito challenge: " + response.get("ChallengeName", "unknown"))
    token = response["AuthenticationResult"]["AccessToken"]
    if not user.get("totp_secret"):
        raise RuntimeError("A verified TOTP authenticator is required for every synthetic user")
    preference = client.set_user_mfa_preference(AccessToken=token,
                                               SoftwareTokenMfaSettings={"Enabled": True, "PreferredMfa": True})
    user["last_auth_evidence"] = {"initial_challenge": initial_challenge,
                                  "authentication_request_id": response["ResponseMetadata"]["RequestId"],
                                  "mfa_preference_request_id": preference["ResponseMetadata"]["RequestId"]}
    save_private()
    return token


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--runtime-dir", type=Path, required=True)
    parser.add_argument("--apply-approved-scope", action="store_true")
    args = parser.parse_args()
    root = args.runtime_dir.resolve()
    checkout = Path(__file__).resolve().parents[2]
    if root == checkout or checkout in root.parents:
        raise SystemExit("Use a private runtime directory outside the repository")
    if not args.apply_approved_scope:
        print(json.dumps({"dry_run": True, "account": ACCOUNT, "pool": POOL, "new_public_client": CLIENT_NAME,
                          "domain": DOMAIN, "callbacks": CALLBACKS, "synthetic_users": ACTORS,
                          "existing_mfa_and_client": "preserved", "messages_sent": 0}, indent=2))
        return
    session = boto3.Session(profile_name="relay-workshop", region_name="us-east-1")
    if session.client("sts").get_caller_identity()["Account"] != ACCOUNT:
        raise SystemExit("Wrong account; no writes")
    cognito = session.client("cognito-idp")
    pool = cognito.describe_user_pool(UserPoolId=POOL)["UserPool"]
    if pool.get("UserPoolTags", {}).get("Project") != "RELAY" or pool.get("MfaConfiguration") != "ON":
        raise SystemExit("Pool ownership/MFA differs from the reviewed plan; no writes")
    if not cognito.get_user_pool_mfa_config(UserPoolId=POOL).get("SoftwareTokenMfaConfiguration", {}).get("Enabled"):
        raise SystemExit("Authenticator MFA is not enabled; no writes or MFA changes")
    manifest_path, private_path = root / "created-resources.json", root / "demo-identities.private.json"
    manifest = json.loads(manifest_path.read_text()) if manifest_path.exists() else {"account": ACCOUNT, "region": "us-east-1", "pool": POOL, "users": []}
    private = json.loads(private_path.read_text()) if private_path.exists() else {}
    def save():
        write_private(private_path, private)
        write_private(manifest_path, manifest)
    if not manifest.get("client_id"):
        if any(c["ClientName"] == CLIENT_NAME for c in cognito.list_user_pool_clients(UserPoolId=POOL, MaxResults=60)["UserPoolClients"]):
            raise SystemExit("A same-name client exists without this manifest; inspect ownership before reuse")
        new = cognito.create_user_pool_client(UserPoolId=POOL, ClientName=CLIENT_NAME, GenerateSecret=False,
                                               ExplicitAuthFlows=["ALLOW_USER_PASSWORD_AUTH", "ALLOW_USER_SRP_AUTH", "ALLOW_REFRESH_TOKEN_AUTH"],
                                               AllowedOAuthFlowsUserPoolClient=True, AllowedOAuthFlows=["code"],
                                               AllowedOAuthScopes=["openid", "email"], SupportedIdentityProviders=["COGNITO"],
                                               CallbackURLs=CALLBACKS, LogoutURLs=["relay://oauth/signout", "http://localhost:8400/signout"],
                                               PreventUserExistenceErrors="ENABLED", EnableTokenRevocation=True,
                                               AccessTokenValidity=60, IdTokenValidity=60, RefreshTokenValidity=1,
                                               TokenValidityUnits={"AccessToken": "minutes", "IdToken": "minutes", "RefreshToken": "days"})["UserPoolClient"]
        manifest["client_id"] = new["ClientId"]
        save()
    if not manifest.get("domain"):
        if pool.get("Domain") or pool.get("CustomDomain"):
            raise SystemExit("A domain now exists; inspect ownership before making changes")
        cognito.create_user_pool_domain(UserPoolId=POOL, Domain=DOMAIN, ManagedLoginVersion=1)
        manifest["domain"] = DOMAIN
        save()
    tokens, members = {}, {}
    for actor in ACTORS:
        username = "relay-mvp-" + actor + "@example.invalid"
        if actor not in private:
            password = "Aa9!" + secrets.token_urlsafe(24)
            try:
                user = cognito.admin_create_user(UserPoolId=POOL, Username=username, TemporaryPassword=password,
                                                MessageAction="SUPPRESS", UserAttributes=[{"Name": "email", "Value": username},
                                                                                          {"Name": "email_verified", "Value": "true"}])["User"]
            except ClientError as exc:
                if exc.response["Error"]["Code"] == "UsernameExistsException":
                    raise SystemExit("A demo username exists without this manifest; no password reset attempted") from None
                raise
            subject = next(a["Value"] for a in user["Attributes"] if a["Name"] == "sub")
            private[actor] = {"username": username, "password": password, "subject": subject, "password_set": False}
            manifest["users"].append({"actor": actor, "username": username, "subject": subject})
            save()
        if not private[actor]["password_set"]:
            cognito.admin_set_user_password(UserPoolId=POOL, Username=username, Password=private[actor]["password"], Permanent=True)
            private[actor]["password_set"] = True
            save()
        tokens[actor] = authenticate(cognito, manifest["client_id"], private[actor], save)
        members[private[actor]["subject"]] = {"role": "dispatcher" if "dispatcher" in actor else "requester",
                                              "incident_id": "synthetic-demo-01", "shelter_ids": ["shelter-" + actor[-1]]}
    write_private(root / "aws-test-tokens.json", tokens)
    config = {"mode": "aws", "storage": "dynamodb", "runtime_dir": str(root),
              "issuer": f"https://cognito-idp.us-east-1.amazonaws.com/{POOL}", "client_id": manifest["client_id"],
              "aws_config_file": os.environ.get("AWS_CONFIG_FILE"),
              "aws_credentials_file": os.environ.get("AWS_SHARED_CREDENTIALS_FILE"),
              "aws_login_cache_directory": os.environ.get("AWS_LOGIN_CACHE_DIRECTORY"),
              "allow_aws_writes_and_ai": True, "max_requests": 30, "max_transcriptions": 5,
              "memberships": members,
              "shelters": [{"shelter_id": "shelter-a", "incident_id": "synthetic-demo-01", "display_name": "Shelter A"},
                           {"shelter_id": "shelter-b", "incident_id": "synthetic-demo-01", "display_name": "Shelter B"}]}
    write_private(root / "aws-config.json", config)
    print(json.dumps({"status": "configured", "client_id": manifest["client_id"],
                      "domain": f"https://{DOMAIN}.auth.us-east-1.amazoncognito.com", "synthetic_users": len(tokens),
                      "mfa": "ON, TOTP enrolled", "tokens": "saved privately, values omitted"}, indent=2))


if __name__ == "__main__":
    main()
