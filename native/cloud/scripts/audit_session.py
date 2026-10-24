"""Read only known RELAY resource metadata; never return credentials or user records."""
import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    session = boto3.Session(profile_name="relay-workshop", region_name="us-east-1")
    config = Config(connect_timeout=5, read_timeout=15, retries={"total_max_attempts": 1})
    report = {"observed_at": datetime.now(timezone.utc).isoformat(), "region": "us-east-1", "checks": {}}

    def check(name, function):
        try:
            report["checks"][name] = {"status": "PASS", "result": function()}
        except ClientError as exc:
            code = exc.response["Error"]["Code"]
            status = "ABSENT" if code in {"NoSuchBucketPolicy", "NoSuchTagSet"} else "DENIED" if "AccessDenied" in code else "FAIL"
            report["checks"][name] = {"status": status,
                                      "code": exc.response["Error"]["Code"],
                                      "request_id": exc.response.get("ResponseMetadata", {}).get("RequestId")}
        except BotoCoreError as exc:
            report["checks"][name] = {"status": "FAIL", "code": type(exc).__name__}

    sts = session.client("sts", config=config)
    identity = sts.get_caller_identity()
    if identity["Account"] != "928489693154":
        raise SystemExit("Wrong AWS account; stopped before any resource inspection.")
    report["identity"] = {k: identity[k] for k in ("Account", "Arn")}
    report["identity_request_id"] = identity["ResponseMetadata"]["RequestId"]
    bedrock = session.client("bedrock", config=config)
    check("nova_lite_availability", lambda: bedrock.get_foundation_model_availability(modelId="amazon.nova-lite-v1:0"))
    check("nova_lite_metadata", lambda: bedrock.get_foundation_model(modelIdentifier="amazon.nova-lite-v1:0")["modelDetails"])
    ddb = session.client("dynamodb", config=config)
    def table():
        t = ddb.describe_table(TableName="relay-messages")["Table"]
        return {k: t.get(k) for k in ("TableName", "TableArn", "TableStatus", "KeySchema", "AttributeDefinitions", "BillingModeSummary", "StreamSpecification", "ItemCount", "TableSizeBytes")}
    check("table", table)
    check("table_tags", lambda: ddb.list_tags_of_resource(ResourceArn="arn:aws:dynamodb:us-east-1:928489693154:table/relay-messages")["Tags"])
    def namespace():
        queue = ddb.query(TableName="relay-messages", KeyConditionExpression="pk = :pk",
                         ExpressionAttributeValues={":pk": {"S": "RELAY_MVP_V1#WORK"}}, Limit=1, ConsistentRead=True)
        counters = [bool(ddb.get_item(TableName="relay-messages", Key={"pk": {"S": "RELAY_MVP_V1#BUDGET"}, "sk": {"S": kind}}, ConsistentRead=True).get("Item"))
                    for kind in ("requests", "transcriptions")]
        return {"work_exists": bool(queue.get("Items")), "budget_records_exist": any(counters),
                "note": "Checks reserved queue/counters only, not a table scan"}
    check("reserved_ddb_namespace", namespace)
    s3 = session.client("s3", config=config)
    bucket = "relay-artifacts-928489693154-use1"
    owned_bucket = {"Bucket": bucket, "ExpectedBucketOwner": "928489693154"}
    check("artifacts_public_access_block", lambda: s3.get_public_access_block(**owned_bucket)["PublicAccessBlockConfiguration"])
    check("artifacts_policy_status", lambda: s3.get_bucket_policy_status(**owned_bucket)["PolicyStatus"])
    check("artifacts_encryption", lambda: s3.get_bucket_encryption(**owned_bucket)["ServerSideEncryptionConfiguration"])
    check("artifacts_tags", lambda: s3.get_bucket_tagging(**owned_bucket)["TagSet"])
    check("artifacts_ownership", lambda: s3.get_bucket_ownership_controls(**owned_bucket)["OwnershipControls"])
    check("reserved_s3_prefix", lambda: {"objects_exist": bool(s3.list_objects_v2(**owned_bucket, Prefix="cloud-mvp-v1/", MaxKeys=1).get("Contents"))})
    cognito = session.client("cognito-idp", config=config)
    pool_id = "us-east-1_f7wyKUgiY"
    def pool():
        p = cognito.describe_user_pool(UserPoolId=pool_id)["UserPool"]
        return {k: p.get(k) for k in ("Id", "Name", "Arn", "Domain", "CustomDomain", "UserPoolTags", "UserPoolTier", "AdminCreateUserConfig", "UsernameAttributes", "AutoVerifiedAttributes")}
    check("cognito_pool", pool)
    check("cognito_mfa", lambda: cognito.get_user_pool_mfa_config(UserPoolId=pool_id))
    def clients():
        result = []
        for c in cognito.list_user_pool_clients(UserPoolId=pool_id, MaxResults=60)["UserPoolClients"]:
            obj = cognito.describe_user_pool_client(UserPoolId=pool_id, ClientId=c["ClientId"])["UserPoolClient"]
            selected = {k: obj.get(k) for k in ("ClientId", "ClientName", "AllowedOAuthFlows", "AllowedOAuthScopes", "AllowedOAuthFlowsUserPoolClient", "CallbackURLs", "LogoutURLs", "ExplicitAuthFlows", "SupportedIdentityProviders")}
            selected["has_client_secret"] = "ClientSecret" in obj
            result.append(selected)
        return result
    check("cognito_clients", clients)
    check("cognito_groups", lambda: [{k: g.get(k) for k in ("GroupName", "Description", "RoleArn")} for g in cognito.list_groups(UserPoolId=pool_id)["Groups"]])
    iam = session.client("iam", config=config)
    check("participant_trust", lambda: iam.get_role(RoleName="WSParticipantRole")["Role"]["AssumeRolePolicyDocument"])
    check("lambda_account_settings", lambda: session.client("lambda", config=config).get_account_settings())
    # Remove SDK HTTP-header metadata; retain request IDs where explicitly selected.
    def clean(value):
        if isinstance(value, dict):
            return {k: clean(v) for k, v in value.items() if k not in {"ResponseMetadata"}}
        if isinstance(value, list):
            return [clean(x) for x in value]
        return value
    report = clean(report)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, default=str) + "\n")
    print(json.dumps(report, indent=2, default=str))


if __name__ == "__main__":
    main()
