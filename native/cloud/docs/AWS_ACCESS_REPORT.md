# RELAY AWS access audit — Team 2

Audit date: **2026-10-23, America/Los_Angeles**. Scope: read-only inspection of the user's open workshop console in Safari, local RELAY documentation, the supplied Team 2 CSV, and current official AWS documentation/public pricing. No AWS resources were created or modified. No model, transcription, endpoint, or training job was invoked. No credentials were displayed, extracted, or exported.

## Decision and immediate blocker

The workshop console is usable, and several proposed services are readable. The account already has RELAY-named DynamoDB and Cognito resources. The main discovered blocker is **the execution role for a normal Lambda backend**:

- Participant role: `arn:aws:iam::928489693154:role/WSParticipantRole`.
- Attached policies: AWS-managed `PowerUserAccess` and customer-managed `ws-default-policy`; no role permissions boundary is set.
- `iam:PassRole` is allowed only for `WSParticipantRole` itself.
- That role's trust policy contains workshop control-plane principals and **does not trust `lambda.amazonaws.com`**.
- The inspected policies provide no normal `iam:CreateRole`, `iam:AttachRolePolicy`, `iam:PutRolePolicy`, or `iam:UpdateAssumeRolePolicy` grant.

Therefore, conventional Lambda deployment with a new dedicated execution role is **not supported by the inspected identity policies**. This is a policy/trust conclusion, not a deliberately attempted failed deployment. Account-level role-manager arrangements, session policies, SCPs, and other grants were not fully inspectable, so do not generalize this into a claim that every possible managed deployment path is impossible. [Lambda execution-role requirement](https://docs.aws.amazon.com/lambda/latest/dg/lambda-intro-execution-role.html), [current PowerUserAccess policy](https://docs.aws.amazon.com/aws-managed-policy/latest/reference/PowerUserAccess.html).

Best next action for the organizer: provide a dedicated RELAY Lambda role and narrowly scoped PassRole access, or provision the small backend stack for the team. Do not solve this by letting Lambda assume the powerful participant role. The implementation plan includes a supervised Mac-hosted backend fallback using the same AWS service interfaces.

## Account, team, and event evidence

| Field | Observed evidence | Interpretation |
|---|---|---|
| Console account | `928489693154` | Live account ID verified in console account header and IAM dashboard. |
| Console session | `WSParticipantRole/Participant` | Console identity verified; `sts:GetCallerIdentity` was not executed independently. This is not an administrator-access claim. |
| Selected region | N. Virginia / `us-east-1` | Use this region for the planned stack. IAM itself is global. |
| Event | `sjsu sparthillhack2026` | User-opened Workshop Studio dashboard and console session inspected. |
| Event access | Start displayed `10/23/2026 03:28 PM`; duration `72 hours`; accessible region `us-east-1` | Access duration is distinct from judging/submission time. The dashboard did not explicitly label the time zone in the extracted text. |
| Team 2 CSV | Team name `Team 2`, state `Provision queued`, blank AWS account ID, last updated `15:20:19 PDT` | Earlier snapshot does not independently map the live account to Team 2. The user's identification of the current contest session was used; obtain live organizer mapping before deployment. Team code and join URL were not exposed. |
| Local programmatic access | No `aws` executable on PATH, no configured AWS config profiles/SSO sections, no credentials file | Console was the available authenticated audit surface. No local environment credentials or browser session secrets were extracted. |
| Role session duration | Maximum 12 hours shown | Maximum duration is not the remaining lifetime of the current session. |
| Visible cost widget | Month-to-date `$0.36`, month-end forecast `$0.49` | Point-in-time account widget, not available credit, team allowance, or a RELAY cost estimate. |

Workshop challenge page: Bedrock must perform actual work inside the application; submission is a **five-minute video** showing architecture, persona/application, and AWS AI in use. It lists a Saturday **10:30 AM** deadline and about 18 build hours across two days. Confirm the organizer's time zone and submission channel. The rubric gives 25 points to the working application and 20 to AWS AI use; prioritize a complete workflow over optional agent infrastructure. [Authenticated challenge page](https://catalog.us-east-1.prod.workshops.aws/event/dashboard/en-US/workshop/challenge).

## Access matrix

**Verified** means the stated console view/data rendered successfully; it is limited to that observation. **Denied** is reserved for an observed denial, or explicitly labeled policy denial. **Unverified** means no successful runtime/write test or sufficient read result exists. No signed CLI/API responses or HTTP request IDs were captured. Console lists are evidence of console read access, not a guarantee about every underlying API.

| Service / capability | Region | Status | Evidence | Blocker or next check |
|---|---|---|---|---|
| Workshop console identity | `us-east-1` | Verified | Account/role header and IAM role ARN agree | Independently run `sts:GetCallerIdentity` once the user configures an authenticated CLI session. |
| IAM role/policy/trust read | Global | Verified | Two attached policies, role boundary absent, JSON policy/trust inspected | Session policies and organization SCPs remain unverified. |
| Organization information | Global | Denied | Guardrails organization-enforcement panel returned `Access denied to organizations:DescribeOrganization`; displayed context: no identity-based policy allows the action | Organization-wide enforced guardrails/SCPs cannot be inferred. No permission change or diagnostic AI call attempted. |
| IAM normal role creation / policy attachment | Global | Unverified; inspected policies provide no grant | PowerUserAccess excludes general IAM management; workshop policy adds read, service-linked role creation, and narrow PassRole | Organizer-provided execution role or explicitly authorized deployment arrangement. No create call attempted. |
| PassRole to RELAY execution role | Global | Unverified; current visible grant insufficient | Only `WSParticipantRole` is passable; it lacks Lambda trust | Dedicated role + narrowly scoped participant PassRole grant. |
| Bedrock console overview | `us-east-1` | Verified | Bedrock runtime overview and service navigation rendered | Overview is not model catalog/inference authorization. |
| Bedrock model discovery | `us-east-1` | Verified in console | Completed catalog showed 262 entries; filter found Nova Lite and opened its model card (`amazon.nova-lite-v1:0`, serverless) | Discovery/model metadata do not prove entitlement or runtime inference. |
| Bedrock model availability / provider activation | `us-east-1` | Unverified | No account-specific availability result obtained | `GetFoundationModelAvailability`; separate agreement, entitlement, authorization and region fields. |
| Bedrock Converse / InvokeModel | `us-east-1` | Unverified | Broad non-IAM service policy suggests access; no invocation | Exact tiny synthetic test below, only after authorization for paid runtime activity. |
| Inference-profile listing | Source `us-east-1` | Verified in console | Completed system-defined list displayed 97 profiles with IDs, ARNs and region descriptions | Candidate-specific Nova Lite lookup remains unverified: UI text filtering unexpectedly hid even a visibly listed Nova entry. Confirm exact ID using `GetInferenceProfile`; do not infer absence or entitlement from this filter. |
| Bedrock applied quotas — Nova Lite | `us-east-1` | Verified in console | On-demand: 4M TPM / 2K RPM. Geo cross-region: 8M TPM / 4K RPM. Completed filtered account quota table | Listed capacity is ample for the proposed demo but does not prove runtime entitlement or spare capacity. “Not supported” appeared under request-quota-increase, not under inference support. |
| Agents Classic list | `us-east-1` | Verified | Completed list displayed 0 agents and maintenance notice | No agent details or mutation inspected. |
| Agents Classic creation eligibility | `us-east-1` | Unverified | Create button visible; generic maintenance notice; no existing agents | Prior account usage determines eligibility. No safe read result established allowlisting. Do not build MVP around Classic. |
| Transcribe job listing | `us-east-1` | Verified | Completed empty job list, no error | Start/get/delete job runtime and audio/object access are separate checks. |
| Transcribe batch / streaming runtime | `us-east-1` | Unverified | No recording upload or job/stream started | Approved short synthetic clip; confirm format, S3 access, applied concurrency. |
| API Gateway listing | `us-east-1` | Verified | Completed APIs `(0/0)` list; no APIs | Create/integration/deploy/auth remain unverified. |
| Lambda function listing | `us-east-1` | Verified | One workshop system function; no RELAY function | System function left untouched; actual available concurrency and deploy ability unverified. |
| Lambda deployment / execution | `us-east-1` | Unverified; visible role blocker | See execution-role analysis | Resolve role and concurrency before deployment. |
| DynamoDB table listing | `us-east-1` | Verified | Existing active `relay-messages`, string `pk` + `sk`, on-demand read/write, no indexes/replicas displayed | Confirm team ownership and existing schema; no item reads or writes performed. Console `0 bytes` is not proof of emptiness. |
| DynamoDB transactional writes | `us-east-1` | Unverified | No write/transaction attempted | Synthetic isolated record and concurrent reservation test after deployment authorization. |
| Cognito user-pool listing | `us-east-1` | Verified | Existing `RELAY-Dispatchers-SpartHill`, ID `us-east-1_f7wyKUgiY`, single-region | No user records, passwords, or client secrets opened. |
| Cognito application login / role authorization | `us-east-1` | Unverified | Pool existence only; login flows not tested | Inspect public-client PKCE/callback/scopes/groups; prove requester/dispatcher/responder separation. Reuse current pool if suitable. |
| S3 bucket listing | Console `us-east-1`, list spans regions | Verified | Two RELAY-named buckets; both displayed in `us-east-1` | No object contents or bucket policies inspected; names do not prove public/private access. |
| S3 object access / Transcribe compatibility | `us-east-1` | Unverified | No upload, object read, or bucket-policy change | Later test a private synthetic object using the intended backend principal. |
| Optional Knowledge Bases listing | `us-east-1` | Verified | Completed list: no Knowledge Bases | Creation/retrieval unverified; service-role constraints matter. Not required for MVP. |
| Optional Guardrails listing | `us-east-1` | Verified | Completed list: 0 account guardrails; one system-defined US guardrail profile | Apply/create unverified; organization-level view explicitly denied. Zero account guardrails does not prove no organization enforcement. |
| Optional AgentCore runtime | `us-east-1` | Unverified | No capability instantiated or runtime invoked | Not required for MVP; service-role constraints also matter for managed integrations. |
| Optional AgentCore console | `us-east-1` | Verified | Overview and Runtime/Harness/Gateway navigation rendered | This is console navigation only; no resource-list or deployment proof. |
| Optional SageMaker/GPU | `us-east-1` | Unverified; deliberately deferred | No model training/hosting requirement established | Evaluate Transcribe first; then inspect GPU quotas/role only if justified. |
| Billing credits view | Global | Verified | Completed page: no credits; remaining, used, estimated remaining and estimated used all `$0.00` | Does not rule out centrally funded workshop usage or organization-level arrangements. |
| Budgets view / team spending ceiling | Workshop/global | Unverified ceiling; onboarding view readable | AWS Budgets showed onboarding/create-budget page with no configured budget displayed | Organizer confirms team allowance, covered services, teardown time and enforcement. No budget created. |

## Permission interpretation

`ws-default-policy` grants:

- `iam:List*`, `iam:Get*`, `iam:Generate*`, and `sts:GetCallerIdentity` on all resources.
- `iam:CreateServiceLinkedRole` for the service-linked-role path.
- `iam:PassRole` for **only** `arn:aws:iam::928489693154:role/WSParticipantRole`.
- An explicit deny outside `us-east-1`, with exceptions for enumerated global/service actions including `bedrock:Invoke*`, IAM, STS, and S3.

The name “AllowIamReadOnly” does not make every matched action read-only; no generation action was executed. `CreateServiceLinkedRole` is not a grant to create a normal Lambda execution role. A policy exception to a deny is not an allow by itself. Do not infer unrestricted cross-region permission, S3 placement permission, or administrator access from these exceptions. Broad PowerUserAccess suggests service actions are permitted where other controls do not restrict them; SCPs, session policies, resource policies, quotas, provider access and payment prerequisites can still block calls.

The role trust includes the workshop's control-plane IAM user and a workshop control-plane account principal. The exact unrelated control-plane principal is intentionally omitted here. No changes were made to trust, policies, account settings, subscriptions, or browser security.

The Guardrails organization panel displayed an actual denied `organizations:DescribeOrganization` request for `arn:aws:sts::928489693154:assumed-role/WSParticipantRole/Participant`, with the context “no identity-based policy allows the action.” Record that result as observed. It differs from what the public current PowerUserAccess document alone might suggest; the audit did not reconcile the effective-policy discrepancy and does not invent an SCP or other cause. Console identity and attached-policy names are insufficient to conclude effective administrator permissions.

## Bedrock choice and current service restrictions

Use standard on-demand **Converse with explicit backend rules**. First candidate: `amazon.nova-lite-v1:0` in `us-east-1`. Its documented regional availability and supported API do not prove this account can invoke it. The US profile `us.amazon.nova-lite-v1:0` can route from N. Virginia to other US regions; verify destination restrictions and quotas before choosing it. [Nova Lite](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-amazon-nova-lite.html), [cross-region policy behavior](https://docs.aws.amazon.com/bedrock/latest/userguide/inference-profiles-support.html).

Current AWS documentation says Agents Classic stopped accepting new customers on July 30, 2026. Eligibility is per account based on prior usage; existing API lists remain available, while creation/inline-agent operations are restricted for ineligible accounts. This recycled workshop account might have history, so zero visible agents cannot establish eligibility either way. The account's console displayed the maintenance notice. Classic is an unnecessary dependency for RELAY. AgentCore is a later option only if a real orchestration/runtime need appears. [Agents Classic maintenance policy](https://docs.aws.amazon.com/bedrock/latest/userguide/agents-classic-maintenance-mode.html).

First invocation of some third-party Bedrock models can initiate Marketplace enrollment and acceptance of model terms; Anthropic models may require a first-use form and other account prerequisites. Amazon models are not listed as Marketplace-product-key models. For this audit, no form, agreement, subscription, or model invocation was submitted. A future third-party test requires reviewing its activation effects first. [AWS model-access documentation](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html).

Amazon Transcribe supports batch and streaming endpoints in `us-east-1`. Use an existing pretrained baseline and editable transcript; no custom ASR training is justified by the evidence. Confirm actual audio format/sample rate, language support, and applied quotas. [Transcribe endpoints](https://docs.aws.amazon.com/general/latest/gr/transcribe.html), [input requirements](https://docs.aws.amazon.com/transcribe/latest/dg/how-input.html).

## Proposed runtime test — not executed

After the remaining read-only availability check and review of model terms, authorize **one** `Converse` request to `amazon.nova-lite-v1:0` through `bedrock-runtime.us-east-1.amazonaws.com`. No tools, files, streaming, subscriptions, or external actions. Use this exact request shape:

```json
{
  "modelId": "amazon.nova-lite-v1:0",
  "messages": [{
    "role": "user",
    "content": [{"text": "Synthetic RELAY test. Extract JSON only with item, quantity, location, and needs_review. Input: Shelter A needs 20 water packs. Do not allocate inventory or call tools."}]
  }],
  "inferenceConfig": {"maxTokens": 128, "temperature": 0}
}
```

Expected functional evidence: returned assistant text with the requested fields, usage token counts, and a successful runtime response; schema validation checks quantity `20`, item water packs, and Shelter A. This proves only that model/endpoint/principal combination at that moment, not deployment, all models, future quota, or full workflow correctness.

Assuming ≤200 billed input tokens and the 128-token output cap, estimated maximum token charge at the checked Nova Lite rates is `200/1000 × $0.00006 + 128/1000 × $0.00024 = $0.00004272`, under $0.0001. Actual bill uses reported usage and any applicable pricing rules. It creates billable usage and may generate audit/usage records; first-use availability still matters. No Marketplace-product subscription is expected for this Amazon model. **The live Nova Lite model card explicitly says using the model agrees to its EULA.** Review that linked agreement and obtain approval that includes this effect before the first use; “Amazon model” does not mean there are no model terms. No playground was opened and no terms were accepted during this audit. Do not switch providers silently.

## Local implementation evidence and next actions

The local `RELAY/README.md` and latest appended `TEST_RESULTS.md` build-5 section report 25 passing software tests and successful physical installs. Those tests were reviewed, not rerun. The files explicitly leave controlled three-device, router-independent physical acceptance unverified. The cloud adapter, authenticated origin-signing, inventory workflow, and cloud idempotency integration still need implementation. Existing AWS table/auth/storage resources are groundwork, not proof those integrations work.

Existing resources observed without inspecting application data:

- DynamoDB: `relay-messages`, active, string `pk` / `sk`, on-demand.
- Cognito: `RELAY-Dispatchers-SpartHill` (`us-east-1_f7wyKUgiY`), created October 23 at 18:51:44 PDT, single-region.
- S3: `relay-artifacts-928489693154-use1`, created October 23 at 19:16:28 PDT.
- S3: `relay-public-webbucket-twmcadnxx1le`, created October 23 at 19:16:38 PDT. The word “public” in its name is not evidence of effective public access; do not use it for private request/audio data without inspecting and validating policies.

These findings supersede any assumption that the account is empty. No resource above was created by this audit. Coordinate with the teammate who provisioned them before altering their schemas, auth flows, lifecycle, or ownership.

1. Confirm the live Team 2 account mapping and allowed incremental spend with the organizer.
2. Resolve Lambda execution-role/PassRole and available-concurrency constraints, or choose the supervised local backend fallback.
3. Complete the model-availability read and authorize the single synthetic runtime test; Nova Lite account quotas have already been inspected.
4. Reconcile the existing DynamoDB table, Cognito pool, and two S3 buckets before creating duplicates or changing configuration.
5. Implement the online request → review → assignment → responder workflow; then add authenticated relay synchronization and demonstrate duplicate-safe inventory transactions.
6. Add optional speech only after the critical path is stable; record the five-minute submission before the contest deadline.

The companion `CLOUD_MVP_PLAN.md` contains the API contract, identity design, transaction rules, prioritized schedule, demo, cost assumptions, and cleanup plan. All console access limitations and unverified operations are intentionally retained; no blanket “AWS access works” conclusion is justified.
