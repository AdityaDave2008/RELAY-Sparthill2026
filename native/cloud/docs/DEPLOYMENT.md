# Local AWS operation and optional HTTPS hosting

Current state: the locally hosted API is verified against real Cognito MFA, DynamoDB, S3, Nova Lite and batch Transcribe. `package_lambda.py` produced a Linux arm64 artifact. AWS CloudFormation `ValidateTemplate` accepted the template; request ID `REDACTED-ID-6faf064c170c`. This is **syntax validation only**, not deployment or IAM/runtime proof.

## Local AWS backend

Use the same `serve` and `worker` commands as `cloud/README.md`, with the private `aws-config.json` generated after approval. Keep both processes running. Browser login/temporary workshop credentials remain on the server. Each process verifies STS account identity on startup. Do not put runtime config containing local credential paths, tokens, TOTP seeds or user passwords into source control.

Typed request state and work leases live in DynamoDB; recording data lives in private S3. A stopped worker leaves accepted requests pending. Restarting a worker resumes durable work; a claimed task may wait up to the 120-second lease. A crash after a Bedrock response but before persistence may cause another bounded model invocation; exactly-once inference billing is not promised. Logical request identity is exactly preserved by conditional transactions. Transcribe uses deterministic names to avoid duplicate jobs.

## Before hosting

Obtain the dedicated organizer role and PassRole permission described in `ORGANIZER_REQUEST.md`. Obtain a separate hosting/cost approval covering two Lambda functions (512 MiB, reserved concurrency 2 each), an HTTP API, a one-minute recovery schedule and two log groups retained for three days. The local-test approval does not include this deployment. Verify account, region, existing resource ownership and remaining workshop lifetime again. Check that the deployment names do not belong to another stack; do not overwrite unexplained existing resources.

The API performs Cognito JWT checks both at API Gateway and in application code. The health route is public and does not invoke AI. No browser origin or public S3 ACL is enabled. Native URLSession needs no CORS change. The default gateway timeout is 29 seconds, so clients must safely replay timed-out operations, particularly audio validation.

Build the artifact locally (no AWS writes):

```sh
cloud/.venv/bin/python cloud/scripts/package_lambda.py --output /tmp/relay-deployment/relay-lambda.zip
cloud/.venv/bin/python cloud/scripts/prepare_deployment.py --config /private/runtime/aws-config.json --code-key cloud-mvp-v1/deploy/relay-mvp-APPROVED_BUILD.zip --output /tmp/relay-deployment/parameters.json
```

After hosting approval and the dedicated role exist, with the workshop profile and private session environment configured, upload and create the stack:

```sh
aws s3 cp /tmp/relay-deployment/relay-lambda.zip s3://relay-artifacts-928489693154-use1/cloud-mvp-v1/deploy/relay-mvp-APPROVED_BUILD.zip --sse AES256 --region us-east-1 --profile relay-workshop
aws cloudformation create-stack --stack-name relay-cloud-mvp --template-body file://cloud/infra/template.yaml --parameters file:///tmp/relay-deployment/parameters.json --tags Key=Project,Value=RELAY Key=Component,Value=cloud-mvp --region us-east-1 --profile relay-workshop
aws cloudformation wait stack-create-complete --stack-name relay-cloud-mvp --region us-east-1 --profile relay-workshop
aws cloudformation describe-stacks --stack-name relay-cloud-mvp --query 'Stacks[0].Outputs' --region us-east-1 --profile relay-workshop
```

The long CLI wait above is an operator command, not an instruction to keep an unattended agent blocked. Check events on failure; do not broaden permissions automatically. For updates, use a reviewed change set and a new artifact key, not a blind create-stack retry. No IAM capability flag is needed because the template creates no IAM resources.

Record the returned BaseUrl and rerun the independent HTTP smoke client against it, including actual Cognito auth, a text request, a short synthetic recording, access isolation and duplicate behavior. Confirm worker recovery through the schedule, durable DynamoDB state and absence of sensitive logs. Update the handoff and manifest with the exact stack, API URL and results. A CREATE_COMPLETE status alone is not a working cloud demo.

The recovery schedule continues to invoke Lambda while enabled, including idle periods. Disable/delete the stack promptly when the approved hosting window ends; local budget counters are not a hard dollar cap. Cleanup preserves the pre-existing pool, table and bucket. The organizer owns lifecycle/removal of the dedicated role.

References: [HTTP API JWT checks](https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-jwt-authorizer.html), [AWS CLI browser sign-in](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-sign-in.html).
