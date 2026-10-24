# RELAY

Emergency communication for the SpartHill Sustainable AI Hackathon 2026.

RELAY helps a neighborhood relief coordinator understand incoming requests and
get accurate resource updates back to disconnected residents. Amazon Bedrock
in `us-east-1` drives the coordinator's main workflow:

- Two-way help requests and location sharing for people close to an emergency.
- One-way warnings for people in the surrounding area.
- Offline message storage and transfer between participating devices.
- Bedrock analysis of every request, situation briefs, and grounded replies.
- Bedrock multilingual warnings, printable notices, pictograms and spoken scripts.
- Bedrock vision to read photographed paper help cards for volunteer review.
- Accessible information and help requests for people without digital devices.

## Native iPhone/macOS application

The complete Swift prototype is in **[`native/`](native/README.md)**, including the
Xcode project, shared Network.framework/SQLite relay engine, native resident and
coordinator interfaces, AWS Transcribe/Bedrock integration, Python backend, tests,
and reproducible demo instructions. Start with [`native/MORNING_DEMO.md`](native/MORNING_DEMO.md).

```sh
cd native
swift test
open RELAY.xcodeproj
```

The Apple app and `native/cloud` backend form one tested stack. The existing
React/Expo/web apps and `services/api` remain intact and use their own contract;
they have not been automatically integrated with the native transport/backend.
Expo Go and a browser do not acquire Apple's peer-to-peer transport merely by
sharing this repository. Physical router-independent acceptance remains a separate
manual test; see [`native/TEST_RESULTS.md`](native/TEST_RESULTS.md).

The `dev` branch contains the team integration snapshot. `main` remains the GitHub
default branch; publication to it uses ordinary fast-forward updates, preserving
existing team history. [Credential/privacy cleanup report](native/PUBLICATION_CLEANUP.md).

## Project status

- [`packages/relay-core`](packages/relay-core): durable browser message storage,
  validated transfer frames, and gateway synchronization, with tests.
- [`services/api`](services/api): persistent message API, automatic Bedrock
  request analysis, grounded response/bulletin drafts, approval and replies,
  plus DynamoDB/Lambda deployment source.
- [`apps/web`](apps/web): integrated resident, coordinator and volunteer screens,
  QR transfers with receiver receipts, printable notices and offline app caching.

The demo targets iOS and Android with a shared React/TypeScript app. Amazon
Bedrock in `us-east-1` drives request understanding and drafts accessible
responses from coordinator source notes; humans approve messages before sending.
Government approval and emergency-service connections are simulated.

## Run and test

Configure AWS only in the ignored `services/api/.env`; use its `.env.example`
as a guide. Set `AWS_REGION=us-east-1`, `AWS_DEFAULT_REGION=us-east-1` and
`BEDROCK_MODEL_ID=us.anthropic.claude-sonnet-5-5`, plus locally configured
credentials. Set `RELAY_TABLE_NAME` to use an existing DynamoDB table; otherwise
the API uses an atomic local file. Never put AWS keys in frontend variables.

```sh
npm install
npm run build:web
npm start
```

Open `http://127.0.0.1:5173`. The app proxies `/api` to the backend on port 8787.
`npm run dev` runs both servers with frontend hot reload. Live AWS is the
default; fixture mode requires explicitly setting `VITE_MOCK_API=true`.

If those ports are already occupied, use:

```sh
RELAY_PORT=8788 RELAY_WEB_PORT=5174 npm start
```

Then open `http://127.0.0.1:5174`. Use separate browser profiles for residents
and coordinators, so each resident has independent phone storage. In **Resident**,
send a help request; in **Coordinator**, review Bedrock's analysis, provide
verified resource notes, prepare a response and approve it. The resident receives
the reply during sync. The warning composer creates translated, printable and
spoken versions. **Volunteer** can read a card photo with Bedrock, check the
fields, then save it as a help request.

```sh
npm test
npm run typecheck
npm run build:api
npm run test:e2e
```

Browser tests use installed Google Chrome and the built app at port 5174
(`RELAY_TEST_URL` overrides it). They invoke real Bedrock and create fictional
demo records in the configured database. The QR test uses camera streams of
real QR images; physical Android/iPhone cameras still need manual testing.
Phone camera access requires HTTPS; see `npm run dev:phone --workspace=@relay/web`.
Native Bluetooth/radio transport is not implemented in the React/web stack. The separate Swift stack is documented under `native/`.

See the [frontend/API contract](services/api/README.md) for AWS deployment and
demo requirements. Lambda/API Gateway deployment source is included; starting
the local app does not deploy those services. Kiro usage and the submission
video remain team tasks.

## Background

Project discussion: [Hackathon Winner Idea](https://chatgpt.com/share/6adbb2f1-0f14-83e8-991f-3a1d025c9f3e).
