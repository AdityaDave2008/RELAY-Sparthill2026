# Dedicated execution-role request — draft, not sent

Please provision `arn:aws:iam::928489693154:role/relay-cloud-mvp-execution` in the team 2 workshop account. It is for two RELAY Lambda functions in `us-east-1`: `relay-cloud-mvp-api` and `relay-cloud-mvp-worker`.

Use the trust document in `cloud/infra/organizer-role-trust.json` and the scoped permissions in `cloud/infra/organizer-execution-policy.json`. Add the single-role, Lambda-only PassRole statement in `cloud/infra/organizer-participant-passrole.json` to the workshop participant role. Return the role ARN after reviewing any workshop restrictions.

The role accesses only the RELAY MVP DynamoDB namespace, the private audio object prefixes, Nova Lite, the batch speech job API and these functions' log groups. Transcribe's Start action has no resource-level ARN restriction; its permission is limited to us-east-1 and our output bucket/prefix, and the service code restricts names/media locations. The Get action is limited to `relay-mvp-*` jobs. No deferred execution/DataAccessRoleArn is requested. The IAM transaction permissions are the underlying DynamoDB GetItem/PutItem/DeleteItem operations, not an invented TransactWriteItems IAM action.

Do not add Lambda service trust to WSParticipantRole, grant it AdministratorAccess, or change its existing trust policy. No IAM resources are created by our deployment template. Please confirm the available Lambda concurrency, API Gateway/EventBridge/CloudFormation permissions and workshop endpoint policy allow this deployment. We will request the user's hosting/spending approval separately and run live endpoint tests after deployment.

References: [DynamoDB transaction IAM](https://docs.aws.amazon.com/amazondynamodb/latest/developerguide/transaction-apis-iam.html), [Transcribe authorization reference](https://docs.aws.amazon.com/service-authorization/latest/reference/list_transcribe.html).
