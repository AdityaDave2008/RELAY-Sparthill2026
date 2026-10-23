# RELAY

Emergency communication for the SpartHill Sustainable AI Hackathon 2026.

RELAY aims to keep essential information moving during disruptions and outages:

- Two-way help requests and location sharing for people close to an emergency.
- One-way warnings for people in the surrounding area.
- Offline message storage and transfer between participating devices.
- AWS support for processing messages when a connection is available.
- Accessible information and help requests for people without digital devices.

## Project status

- [`packages/relay-core`](packages/relay-core): offline message model,
  storage, and store-and-forward sync between devices, with tests.
- The mobile app, the device-to-device transport, and the AWS uplink have
  not started.

The proposed demo targets iOS and Android with a shared React/TypeScript app
and Amazon Bedrock. These are planning notes, not implemented capabilities.
Government approval and emergency-service connections would be simulated in
the demo; live integrations require agency partnerships.

## Background

Project discussion: [Hackathon Winner Idea](https://chatgpt.com/share/6adbb2f1-0f14-83e8-991f-3a1d025c9f3e).
