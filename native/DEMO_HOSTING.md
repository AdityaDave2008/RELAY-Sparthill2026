# RELAY demo hosting

Current API: **https://relay.stepcheck.app**.

The API and worker run on this Mac. Namecheap DNS points to CloudFront, which
forwards authenticated HTTPS/WebSocket traffic through the existing Cloudflare
Quick Tunnel to loopback port8788. Real AWS Cognito, DynamoDB, Transcribe, Bedrock
and S3 are used. A custom domain does not move compute off this Mac.

See [current hosting instructions](cloud/docs/DEMO_HOSTING.md),
[the morning rehearsal](MORNING_DEMO.md), and [actual evidence](TEST_RESULTS.md).
The earlier random tunnel URL remains the origin; don't restart it casually.
If that URL changes, update the distribution origin, not the phone endpoint.

The API must stay awake and online for speech/AI/inventory. Native nearby request
and receipt delivery can work independently of the API after setup is cached.
Physical router-free radio acceptance remains a separate test.
