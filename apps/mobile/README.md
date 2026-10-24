# @relay/mobile

RELAY's iOS + Android app, built with **Expo (React Native) + TypeScript** and
**Amplify UI** for authentication. It imports the shared offline core
(`@relay/core`) and talks to the RELAY REST API in
[`services/api`](../../services/api/README.md).

> The RELAY backend is a hand-written REST API over DynamoDB + Bedrock. It is
> **not** an Amplify-provisioned backend. Amplify here is only the client-side
> auth UI (Amazon Cognito via Amplify UI's `<Authenticator>`). The backend is
> unchanged.

## Why not Expo Go

Amplify requires native modules that are not in the Expo SDK, so **Expo Go is
not supported**. Use a development build (`expo run:ios` / `expo run:android`),
which is what the scripts below do. (Source: Amplify UI React Native install
docs, rephrased for compliance with licensing restrictions —
https://ui.docs.amplify.aws/react-native/getting-started/installation)

## Project structure

```
apps/mobile/
  app.json              Expo config: iOS bundle id, Android package, permissions
  index.ts              Entry point (crypto polyfill + registerRootComponent)
  metro.config.js       Monorepo-aware Metro config (resolves @relay/core source)
  babel.config.js       babel-preset-expo
  src/
    App.tsx             Root; optional Amplify Authenticator gate
    config/
      amplify.ts        Cognito configuration (optional, env-driven)
      env.ts            API URL + demo token resolution
    relay/
      deviceId.ts       Stable per-install device id
      persistence.ts    AsyncStorage <-> @relay/core SnapshotPersistence bridge
      useRelay.ts       Opens MessageStore, exposes messages + sync()
    screens/
      ResidentScreen.tsx  Compose help request, view outbox, sync
```

Native `ios/` and `android/` folders are generated on demand by
`expo prebuild` / `expo run:*` and are git-ignored.

## Setup

From the repository root (dependencies are installed for all workspaces):

```sh
npm install
```

Copy the environment template and fill in values:

```sh
cp apps/mobile/.env.example apps/mobile/.env
```

- `EXPO_PUBLIC_API_URL` — the RELAY API. Default `http://127.0.0.1:8787`. On a
  physical device use your machine's LAN IP.
- `EXPO_PUBLIC_DEVICE_TOKEN` — shared demo device token (needed outside loopback).
- `EXPO_PUBLIC_COGNITO_*` — optional. Leave blank to run with no auth gate.

## Run

Start the local API first (from the repo root):

```sh
npm run dev:api
```

Then build and launch the app (requires Xcode for iOS, Android SDK for Android):

```sh
npm run ios      --workspace=@relay/mobile   # or
npm run android  --workspace=@relay/mobile
```

Type-check only:

```sh
npm run typecheck --workspace=@relay/mobile
```

## What's wired vs. left as integration points

Wired:
- Durable offline store via `@relay/core` `MessageStore` on AsyncStorage.
- Help-request composition and gateway sync against the REST contract.
- Optional Cognito auth via Amplify UI.
- iOS/Android project config with camera + location usage strings/permissions.

Left for follow-up (owned by the frontend/transport integration per the API
README): camera + QR rendering/scanning for device-to-device transfer, map/zone
UI, the coordinator dashboard screens, and push notifications.
