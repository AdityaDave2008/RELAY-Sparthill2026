# Request extraction and live updates — build19

The app sends the reviewed transcript (or typed text) to a durable pre-send preview.
AWS Transcribe supplies text; Amazon Nova Lite on Bedrock supplies structured fields.
Bedrock uses `Converse` with one forced `extract_request` tool whose input schema is
our `ModelProposal`. This tool reports data only; nothing from the model is executed.
[AWS tool-definition documentation](https://docs.aws.amazon.com/nova/latest/userguide/tool-use-definition.html)
and [structured-output guidance](https://aws.amazon.com/blogs/machine-learning/structured-outputs-with-amazon-nova-a-guide-for-builders/)
explain the API mechanism. The server still validates every result.

Quantity evidence must refer to a resource count, not a people count, age, room or
medicine strength. Unknown stays null. People and landmarks are separate fields.
Landmark/medicine details must be source text. Urgency requires explicit wording
and a supporting quote; it is reported urgency, not clinical triage. The native
form permits user corrections before immutable submission and encrypts these fields
in the nearby copy. An AI tag cannot approve stock. Medicines are staff-reviewed
requests; a medication-specific stock catalogue is future work.

The original source-wide number/negation rules incorrectly treated narrative as
conflicting quantities or cancelled requests. Missing-field annotations also rejected
otherwise useful output when Nova named an optional field. The server now derives
those annotations, preserves validated known fields, and shows readable review notes.
Invalid JSON/extra fields remain explicit review failures. No hidden paid repair call
or automatic medication/dose suggestion is made. The user can enter details manually.

For this Mac origin, `accelerate_previews=true` enables one bounded preview worker
inside the API process. It claims the same durable conditional lease as the ordinary
worker, so a concurrent worker/retry cannot invoke the same job twice. Capacity
exhaustion leaves work in the durable queue; restart recovery is unchanged. Default
configuration leaves this optional lane disabled for other deployments.

`GET /v1/requests/{id}/snapshot` returns authorized request/history/reservation data
with one batched read. The native foreground detail view checks about every3s,
list about every8s, directory about every60s. Replies/stock operations keep immutable
operation IDs; delayed snapshots cannot erase pending actions or newer history.
This is polling, not background push or offline staff-reply delivery. User-reported
latency still includes internet/provider time and foreground scheduling.

Current real synthetic samples and test counts are in the top of TEST_RESULTS.md.
The runtime remains on the Mac behind relay.stepcheck.app; Namecheap is DNS, not
compute hosting. No AWS credentials are sent to the native app.
