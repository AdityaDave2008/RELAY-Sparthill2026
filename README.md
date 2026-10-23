# RELAY

Emergency communication for the SpartHill Sustainable AI Hackathon 2026.

RELAY aims to keep essential information moving during disruptions and outages:

- Two-way help requests and location sharing for people close to an emergency.
- One-way warnings for people in the surrounding area.
- Offline message storage and transfer between participating devices.
- AWS support for processing messages when a connection is available.
- Accessible information and help requests for people without digital devices.

## Project status

- [`packages/relay-core`](packages/relay-core): durable browser message storage,
  validated transfer frames, and gateway synchronization, with tests.
- [`services/api`](services/api): persistent message API, automatic Bedrock
  request analysis, grounded response/bulletin drafts, approval and replies,
  plus DynamoDB/Lambda deployment source.
- The frontend is being developed separately. Physical-device camera/radio
  transfer and the full user-interface demo still need integration testing.

The demo targets iOS and Android with a shared React/TypeScript app. Amazon
Bedrock in `us-east-1` drives request understanding and drafts accessible
responses from coordinator source notes; humans approve messages before sending.
Government approval and emergency-service connections are simulated.

Start the API with `npm install` and `npm run dev:api`. Configure AWS only in
the ignored `services/api/.env`; use its `.env.example` as a guide. See the
[frontend/API contract](services/api/README.md) for integration and live testing.

## Background

Project discussion: [Hackathon Winner Idea](https://chatgpt.com/share/6adbb2f1-0f14-83e8-991f-3a1d025c9f3e).
