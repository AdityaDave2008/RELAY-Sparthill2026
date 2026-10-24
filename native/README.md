# RELAY — offline store-carry-forward prototype

Buildable SwiftUI iOS and macOS apps sharing a Swift/Network.framework/SQLite engine. The relay remains local and uses no third-party runtime dependencies or external radio hardware. Build22 adds profile photos, explicit per-request personal-detail sharing, a dedicated login screen and cleaner Help navigation to the existing alerts/live-speech/encrypted-shelter workflow. The HTTPS API still runs on this Mac.

**Current verdict:** automated protocol tests, separate-process TCP loopback experiments, and native Mac ↔ iOS Simulator Bonjour control exchanges pass. **Physical iPhone A → iPhone B → Mac C and infrastructure-independent wireless delivery have NOT been verified.** See [TEST_RESULTS.md](TEST_RESULTS.md) for evidence and blockers. A simulator is not a radio test.

## Current workflow — build 22

The interface follows the plain reference: white backgrounds, bold system text,
large outlined controls, a brown active accent, and functional text-size / contrast
settings. Public tabs are **Ask for help / Requests / Alerts / Settings**. Coordinator tabs
are **Inbox / Inventory / Alerts / Settings**. Nearby chat and engineering tools are inside
Settings. [Design notes](DESIGN.md).

- **Resident profile:** photo and personal details live in Settings. Display name
  and preferred language are required when saving; photo and health fields remain
  optional, with first-run Skip for now. Review offers explicit sharing of selected
  text with the destination shelter, off by default. Photo stays local; attached
  fields are excluded from AI extraction. Sent snapshots persist with the request.
  A small question-mark icon beside Ask for help opens the six-page walkthrough.
  Signed-out users see a dedicated account login; cached users retain offline access.
  [Privacy, compatibility and testing](docs/RESIDENT_SETUP.md).

- **Speak or type:** live AWS Transcribe displays partial words. Review the final
  editable transcript, get a Bedrock proposal, correct quantities and send explicitly.
  Both live speech and Bedrock require internet; typed requests work from cached setup.
- **Details and urgency:** Bedrock extracts supply counts separately from people,
  location text and reported urgency. Review or manually choose Routine, Soon,
  Urgent or Immediate; unknown urgency stays unset. Requested units are editable.
  Medicines requests retain the medicine name/details for staff review; they do
  not allocate generic medicine stock or generate dosing/prescribing advice.
  [Extraction and refresh behavior](cloud/docs/EXTRACTION.md).
- **Alerts:** dispatchers review/publish incident-wide announcements with priority,
  expiry and withdrawal. Residents see unread notices and can listen using the
  installed system voice. Downloaded alerts/read state survive restart. New alerts
  and withdrawals need cloud refresh; they are not P2P broadcasts or push notifications.
  [Contract, identity and testing](cloud/docs/ANNOUNCEMENTS.md).
- **Shelter information:** authorized staff publish address, optional coordinates
  and arrival instructions from Settings. Residents can view cached instructions,
  calculate straight-line distance from a location snapshot and open the point in
  Maps. No safe route or travel-time assertion is made.
- **Location:** new requests require a snapshot OR a typed address/landmark/room.
  Permission is requested only after tapping a location button.
  Coordinates, accuracy and capture time are included in the reviewed request.
  No continuous tracking. GPS permission itself is not mandatory. Historical
  queued messages retain their original bytes and remain retryable.
- **One request, two routes:** the main form durably saves one immutable request ID.
  Cloud delivery and an encrypted nearby copy can reach the same enrolled shelter
  receiver. Carriers store ciphertext; only the addressed receiver decrypts it.
  A signed destination receipt can return through a later encounter. Relay storage,
  shelter receipt, cloud acceptance and staff approval remain distinct.
- **Authorized gateway:** a coordinator uploads the carried sender-signed request.
  The backend checks the enrolled origin key/current membership and retains the
  original requester as owner. A later direct upload deduplicates the same ID/body.
- **Inventory:** staff approve/reserve, confirm handover or release stock. These
  are atomic server ledger operations, require cloud access, and cannot be triggered
  by the model. Staff replies and inventory status synchronize through the cloud;
  only the destination delivery receipt currently returns through the nearby path.
- **Preparation:** accounts and shelter receiving keys must be enrolled/cached
  while online before the offline demonstration. Every participating app must stay
  open during encounters. Background/terminated forwarding is not promised.
- **Identity:** Cognito account subject + configured incident membership authorize
  data access. A separate persistent device UUID/key pair handles nearby routing.
  Each resident needs a separate organizer-provisioned account; sharing one login
  shares the account's permissions/history. There is no public self-registration
  or user-selectable dispatcher role in this demo.

Use [MORNING_DEMO.md](MORNING_DEMO.md) for the two-phone/Mac rehearsal and
[TEST_RESULTS.md](TEST_RESULTS.md) for the boundary between tested software and
physical wireless claims. The current API is **https://relay.stepcheck.app**.
It still runs on this Mac, using real AWS services behind the TLS tunnel/proxy.
See [hosting details](cloud/docs/DEMO_HOSTING.md) and
[live speech details](cloud/docs/STREAMING.md). No always-on PC or managed AWS
compute deployment is claimed.

## Build and install

Tested using Xcode 26.1.1 (17B100), Swift 6.2.1, iOS/macOS 26.1 SDKs on an M3 Pro Mac. Deployment targets are iOS 17 and macOS 14; older supported OS versions have not been tested. The package uses Swift 5 language mode with explicit serial-queue confinement.

From this directory:

```sh
# No dependency downloads or project-generator installation needed.
open RELAY.xcodeproj

# Native Apple-silicon Mac; ad hoc signing supports local development.
# Keep DerivedData outside file-provider-backed Documents folders.
xcodebuild -project RELAY.xcodeproj -scheme RELAY-macOS \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/RELAY-mac-build build
open /tmp/RELAY-mac-build/Build/Products/Debug/RELAY-macOS.app

# Simulator compile (not a physical P2P test).
xcodebuild -project RELAY.xcodeproj -scheme RELAY-iOS \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/RELAY-sim-build CODE_SIGNING_ALLOWED=NO build

# Device-SDK compilation without signing; this cannot be installed on a phone.
xcodebuild -project RELAY.xcodeproj -scheme RELAY-iOS \
  -configuration Debug -destination 'generic/platform=iOS' \
  -derivedDataPath /tmp/RELAY-ios-build CODE_SIGNING_ALLOWED=NO build
```

For **each physical iPhone**, connect it to Xcode, unlock it, trust this Mac, enable Developer Mode when requested, select the `RELAY-iOS` scheme and that device. In Signing & Capabilities choose your Apple development team and a bundle identifier your team can provision. Build and Run. No developer credentials are bundled. The iOS project currently names the enrolled team and its registered bundle ID; use your own team/identifier if building elsewhere. Both original physical phone development installs and the enrolled-team release archive have succeeded. A free Personal Team may suffice for local development, subject to Apple's provisioning limits.

For stable macOS Local Network permission behavior across rebuilds, use your own development signing identity when available. The committed Mac settings use local ad hoc signing and the App Sandbox's network client/server entitlements. No multicast entitlement is requested: the app only browses/advertises its declared Bonjour service and uses unicast TCP. Allow the normal Local Network and firewall prompts for RELAY during your test; record what appears. No Bluetooth, hotspot, or Wi-Fi Aware entitlement is used. Build 13 adds location purpose strings and the macOS sandbox location entitlement for optional one-shot cloud requests.

The project is checked in. `python3 scripts/generate_project.py` deterministically regenerates its two app targets, shared schemes, and plists using only Python's standard library. It resets signing changes to the project defaults: enrolled team U4G9LV39GM / com.nikilthalapaneni.relay for iOS, ad hoc signing for macOS. Override DEVELOPMENT_TEAM and PRODUCT_BUNDLE_IDENTIFIER on the command line when using another team.

## Shelter requests (build 7)

The historical build 7 interface had **Help, Requests, Shelters, Messages**; these offline shelter tools now live under Settings → Demo tools. Help's gear opens
Settings/Tools; **Help → Nearby devices** opens discovery and peer messaging.
The existing Chats interface is retained under Settings → Nearby messages.

- **Shelters:** create a synthetic shelter received by this device, configure a
  different device's UUID, or import a shared `RELAY-SHELTER-1:` code. The code is
  base64-encoded JSON, not encryption. A shelter UUID is separate from its receiving
  device UUID. Entries persist in SQLite and cannot silently redirect an existing ID.
- **Help:** choose a saved shelter even when absent, enter need, details, quantity/unit,
  optional people count, and location/landmark. Blank quantity/people mean unknown.
  The draft persists while editing and survives restart. Review precedes submission.
- **Requests:** My requests shows sent requests; Device inbox shows help requests
  addressed to this device. These are local test views, **not authenticated staff roles**.
  Carried copies are excluded from both views and from personal chat.
- Submission atomically inserts the immutable message and clears that submitted
  draft. Its ID is reused on retry. A new form remains available after sending.
  Delivery details keep local save, relay ACK, destination receipt and staff progress
  separate. These legacy offline tools do not control the authenticated inventory ledger; use the current main workflow for staff actions.
- Structured help content is versioned JSON inside a reserved `payload.text` prefix
  (`RELAY-HELP-1` followed by a newline), preserving the v1 transport envelope and
  byte-for-byte forwarding through older relay codecs. Older apps can carry it but
  do not provide the new request UI. This describes the legacy build7 format; use the current build on all endpoints.
- SQLite schema 3 adds a shelter directory and durable draft metadata. Existing
  device identities, message bodies, peers and receipt state are preserved.

To try it: on C, **Shelters → Create shelter on this device**. Save a synthetic
name/area, then open the entry and use **Share shelter code** to transfer the full
code to A (for example via AirDrop or Messages before your isolated radio test).
**Copy code only copies on C**, and does not transfer anything automatically.
On A, **Shelters → Import shelter**, paste the full code, check the name and
receiving-device preview, then import. Connect is not needed for directory setup.
Open the imported entry and tap **Request help here**. Help only offers shelters
received by another device; a shelter received here is still visible in Shelters.
Review/save while connections are paused. Start A/B, then B/C in separate encounters
as described in TEST_PLAN.md. On C, open **Requests → Device inbox**. Return B to A
for the receipt. Shelter setup is local and unverified; use synthetic data only.

Open a mistaken entry and use **Remove shelter**. This hides the local directory
entry and clears that destination from an unsent draft. It preserves draft text,
request history, queued messages and receipts; queued delivery continues. Restore
it from **Removed shelters**, or import its identical code again. Removal does not
revoke a shelter on other devices. Removed entries still count toward the prototype
limit of 100 saved entries.


## Chat interface (retained from build 5)

- **Chats:** conversations grouped by the other device, with an always-visible New chat button in the list. Open a chat to see incoming/outgoing bubbles, timestamps, and delivery state. The bottom input stays available after sending; send repeatedly without opening another sheet. Done dismisses the keyboard. Drafts are retained in memory per conversation while the app runs, but unsaved drafts are not durable.
- **New chat:** choose a connected or previously encountered device, or enter its full UUID. Selecting an existing peer opens the same conversation. Invalid/self destinations cannot open a new chat.
- **Nearby:** Connect/Pause controls, connected and remembered peers, and Message this device to open a chat. Forwarding, retry, persistence, and receipts still run through the shared relay engine.
- **Names:** Tools → Edit name sets the name other devices see in Nearby, New chat, and existing conversations after reconnecting. Names persist across restart; every device can send, receive, and carry. A short UUID stays below each name to distinguish duplicate names. Routing and conversation grouping always use the full stable UUID, never the display name. Names are not authenticated identities. Devices that have not yet exchanged a name show a Device + short-ID fallback.
- **Tools:** device-name editing and ID copy/share; test roles under **Advanced relay test**; **Open durable queue** for forwarding/receipt metadata; and diagnostics/fault injection. Carried requests and receipt envelopes are excluded from personal chats. Forwarding copies explicitly say they are not addressed to you, and their payload text is hidden in the queue, including expanded rows. Legacy chat and shelter-code payloads remain plaintext; hiding those rows is presentation separation. Main-workflow encrypted shelter requests are described above. No stored messages are deleted. Tap a personal chat bubble for delivery details.
- Standard body-sized message text, adaptive light/dark colors, width-limited bubbles, compact connection controls, and 44-point send targets. Receipt confirmation remains distinct from a relay's storage acknowledgement.

For a **two-phone test**, turn off **Tools → Advanced relay test → Force A → B → C** on both, tap **Connect**, then **Nearby → Message this device**. Type a synthetic message in the fixed bottom input and tap the send arrow. New stores default to direct mode; existing saved test settings are preserved. Keep the Mac and simulator paused during the two-phone test. Read the no-internet/no-router setup in TEST_PLAN.md before claiming offline success.

## Run the demonstration

Follow [TEST_PLAN.md](TEST_PLAN.md), including network isolation and evidence capture. The essential sequence is:

1. Install on two physical iPhones and the Mac. Select Sender A, Relay B, Receiver C. Each app shows its persistent UUID. Record C's UUID and enter it as A's destination even if they never discover one another. **Role labels are not addresses.**
2. Leave **Tools → Advanced relay test → Force A → B → C** enabled for a close-range logical test. Changing role or route mode reconnects peers if networking was already active. This blocks application messages between A/C, not their radio reachability.
3. Disable cellular/internet, detach conventional Wi-Fi infrastructure while leaving Wi-Fi/Bluetooth radios on, remove tethering/Ethernet/VPN paths, and collect the evidence described in the test plan.
4. Keep C stopped. Tap Start nearby connections on A and B; wait for Connected. A saves `SYNTHETIC M001: Shelter A needs 20 water packs` addressed to **C's UUID**. Record the actual generated message UUID; `M001` is just a test label.
5. Wait for B's `PERSISTED` and A's `RELAY_STORED` ACK. Stop A, terminate B, relaunch B, and verify the same message and device UUID remain. Do not uninstall or erase app data.
6. Start B and C; keep A stopped/out of range. B forwards automatically. C records one request and generates a separate receipt; B persists that receipt.
7. Stop C, stop/restart B if desired, then start B and A. A recognizes the returned receipt and displays **Final destination receipt received**. A's earlier relay ACK must never be mistaken for this state.
8. Repeat with A and C genuinely out of direct range, with forced routing disabled on all devices, before claiming physical separation.

Apps must remain **foreground and awake** during encounters. Nearby services start automatically when the app becomes active; diagnostics can pause them. Once running, discovery, connection, inventory, forwarding, and retries are automatic. iOS background/terminated discovery is not implemented or promised.

## Teammate beta distribution

See [TESTFLIGHT.md](TESTFLIGHT.md) for current upload and availability evidence.
Build19 uploaded on24 October at07:56:48PDT. Upload alone does not establish
external tester approval. The configured [TestFlight invitation](https://testflight.apple.com/join/paGggTvE)
requires an approved build available to its tester group.

Both original phone apps now report build19 and launched successfully, with their
previous data preserved. The original development bundle `org.relay.prototype.ios` and paid
bundle `com.nikilthalapaneni.relay` are separate apps with separate stores. Update
in place; do not uninstall to troubleshoot. No cross-bundle data migration is claimed.

## Automated checks

```sh
xcrun swift test                 # XCTest unit/integration tests; simulated byte transport
xcrun swift build
python3 scripts/tcp_experiment.py # three OS processes using real TCP on 127.0.0.1
```

`tcp_experiment.py` launches three `RelayLab` processes with temporary SQLite stores. It cuts a frame, reconnects, duplicates the same ID, terminates/restarts B between encounters (twice), and checks A → B → C → B → A. It uses explicit loopback addresses and no Bonjour. Its printed logs contain actual UUIDs and assertions; its temporary databases are removed afterward. It does **not** test wireless, range, physical phones, local-network permission, or disaster resilience. A separate native Mac ↔ iOS Simulator control tested Bonjour and the UI; see the evidence files.

## Design and wire format

- `Sources/RelayCore/Protocol.swift`: versioned JSON, message validation, 4-byte unsigned big-endian byte count followed by UTF-8 JSON. No newline delimiter. Maximum JSON frame: 256 KiB; request text: 16 KiB.
- `Store.swift`: SQLite WAL, `synchronous=FULL`, transactions, stable device identity, messages, attempts/ACKs, settings, known peers, and timestamped events. Stored at the app's Application Support/RELAY/relay.sqlite; the UI displays the exact path.
- `Engine.swift`: transport-independent session state machine. Exchange `hello`, then `inventory`, then missing `message` packets and durable-storage `ack` packets. No continuous end-to-end route is needed.
- `NetworkTransport.swift`: Bonjour `_relay-poc._tcp`, NWBrowser/NWListener/NWConnection, TCP, `includePeerToPeer=true` for browser/listener/dialer and cellular prohibited. The lexicographically smaller service UUID dials; both sides browse/listen. A one-second timer drives reconnect checks and eight-second unacknowledged-message retries, with ten-second dial cooldown, five-second inventories, handshake/connect/idle timeouts, and at most eight connections.
- `Conversations.swift`: presentation-only grouping of personal requests into peer conversations; excludes carried traffic and receipt envelopes without modifying the durable store.
- `App/RelayApp.swift`: one SwiftUI chat interface for both targets; test roles, destination UUID/manual or known peer, queue and receipts, paths, persistent logs, forced route, forced duplicate, and partial-frame fault injection. UI updates cross back to the main queue; all SQLite/protocol/network operations use one serial engine queue.

Example request (UUIDs below are illustrative, not test evidence):

```json
{
  "protocol_version": 1,
  "message_id": "REDACTED-ID-b9addbaef9b5",
  "origin_id": "REDACTED-ID-39d3159fe171",
  "destination_id": "REDACTED-ID-2834148914b1",
  "message_type": "RESOURCE_REQUEST",
  "payload": { "text": "SYNTHETIC Shelter A needs 20 water packs" },
  "created_at": "2026-10-23T22:00:00Z",
  "expires_at": "2026-10-24T22:00:00Z",
  "hop_count": 0,
  "max_hops": 5
}
```

The TCP frame contains an envelope, for example `{"protocol_version":1,"kind":"message","message":{...}}`. Other envelopes carry `peer:{device_id,role}`, `inventory:[uuid,...]`, or `ack:{message_id,acceptance}`. The shared decoder rejects unsupported versions, malformed packet shapes, invalid UUIDs, out-of-bounds frames, clocks/TTLs, and hops. IDs use canonical lowercase UUIDs; dates are UTC ISO8601 at whole-second precision.

Hop count increments **per forwarding edge**, not per retry. A message arriving on its last permitted hop may be delivered but cannot be forwarded further. Default max hops is 5; validation permits 1–16. A duplicate can improve the stored hop count if it arrived by a shorter route. Its immutable content must match; a conflicting body with the same UUID is rejected.

A relay ACK means that peer committed the message to SQLite. Even `DESTINATION_STORED` is an immediate storage ACK, not the return-receipt UI state. The final destination atomically inserts the request and a **separate UUID receipt**, which references `payload.original_message_id`, reverses origin/destination, and has its own 24-hour lifetime and the request's hop limit. Receipts use the same store-carry-forward protocol; they do not generate receipts of receipts. On the original sender, a matching receipt updates delivery state in the same transaction as receipt insertion. The claimed receipt origin must equal the request destination; this is a consistency check, **not cryptographic authentication**.

Unique SQLite message IDs and atomic receipt creation suppress duplicate application actions. A lost ACK causes retransmission even when a later inventory contains the ID. TCP send completion never updates delivery state. Partial frames are discarded on disconnect; the original remains queued. Expired messages remain visible for diagnosis/deduplication but are omitted from inventory and forwarding. Expiration uses device wall clocks (up to 5 minutes future skew accepted; TTL up to 7 days). Clock synchronization is an operator prerequisite.

Prototype limits: 1,000 stored messages including receipts, 10,000 retained event lines, 300 log lines loaded into the UI (100 shown); Copy diagnostic log exports all retained lines. Exceeding message capacity rolls back insertion and sends **no ACK**. There is no automatic message purge or administrative reset UI. Preserve/export evidence before uninstalling or intentionally resetting a test install; reinstalling can change the device address. Exactly-once behavior is limited to the durable logical insert and receipt creation, not arbitrary external side effects.

## Wi-Fi transport and developer launches

Messages use Bonjour discovery and Network.framework TCP with Apple peer-to-peer Wi-Fi enabled. This app does not implement a Core Bluetooth message transport. A connection can still use an available conventional network; peer-to-peer opt-in alone is not proof of router independence. Keep the test conditions and actual PATH logs together when evaluating offline results.

During development, the paired Mac can install and explicitly launch RELAY with Apple's `xcrun devicectl device process launch` command. That uses the trusted developer connection (USB or a supported paired local-network connection). It is separate from RELAY's message protocol; the prototype has no remote-launch feature.

## Apple API selection and path evidence

Reviewed current official docs and the installed SDK declarations before implementation:

- [TN3151 — Choosing the right networking API](https://developer.apple.com/documentation/technotes/tn3151-choosing-the-right-networking-api): recommends Network framework and documents opt-in Apple peer-to-peer Wi-Fi; current guidance marks Multipeer Connectivity deprecated in 2026.
- [TN3111 — iOS Wi-Fi API overview](https://developer.apple.com/documentation/technotes/tn3111-ios-wifi-api-overview): distinguishes Apple peer-to-peer Wi-Fi from Wi-Fi Aware and describes device/API scope. Apple peer-to-peer was chosen for this Apple-only prototype; no Wi-Fi Aware pairing flow is required.
- [NWParameters.includePeerToPeer](https://developer.apple.com/documentation/network/nwparameters/includepeertopeer): enables peer-to-peer link technologies. **It is not an assertion that a particular connection used them.**
- [NWBrowser](https://developer.apple.com/documentation/network/nwbrowser), [NWListener](https://developer.apple.com/documentation/network/nwlistener), [NWConnection](https://developer.apple.com/documentation/network/nwconnection): the installed SDK supports all APIs used here.
- [TN3179 — Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy): local-network access, explicit Bonjour service declarations, and multicast entitlement boundaries. Both Info.plists contain `NSLocalNetworkUsageDescription` and `NSBonjourServices = [_relay-poc._tcp]`.

Diagnostics report discovery interfaces, connection path interfaces/types, local/remote endpoints, path state, expense, and cellular status when available. These observations are **not** conclusive evidence of AWDL selection or lack of router mediation. The app intentionally displays infrastructure independence as UNVERIFIED. A Wi-Fi interface, link-local address, or `awdl0` in a browser result alone is insufficient. Qualify the actual operating conditions and capture traffic/path evidence as described in [TEST_PLAN.md](TEST_PLAN.md).

## Security and disaster-resilience limitations

Synthetic demo data only. New main-workflow nearby requests use Apple's CryptoKit
X25519/HKDF/ChaChaPoly and P256 sender signatures; their final receipts require the
cached shelter signing key. The cloud uses HTTPS and Cognito membership checks.
These changes do not authenticate Bonjour hellos, inventory advertisements or
transport storage ACKs. Legacy chat and legacy shelter-code messages remain
plaintext and their older receipts are unauthenticated. Never put private location
or health data in those legacy tools.

Device keys persist in an app-sandbox file with owner-only permissions and iOS file
protection. They are not hardware-bound or independently audited. Decrypted
requests, transcripts and keys are accessible to a compromised endpoint; SQLite
itself is not application-encrypted. Offline sender identity is pending the server's
registered-key check. Peer IDs and traffic metadata remain visible, and malicious
peers can deny service or exhaust bounded queues. No production confidentiality,
organizational certification, key-revocation system or disaster-resilience claim
is made. See [the encrypted transport notes](cloud/docs/NEARBY_DELIVERY.md).

Not a production emergency communication system. Delivery depends on foreground encounters, functioning radios, adequate power/storage, permissions, compatible OS behavior, and honest peers with usable clocks. No end-to-end route planning, redundancy guarantee, congestion control, background wake strategy, attachment transport, or failure-rate/energy/range characterization is provided. Physical tests and longer repeated-failure trials must precede any disaster-resilience claim.

### Name compatibility and storage upgrade

Build 5 adds the optional `display_name` field to the version-1 hello packet. Old peers can ignore it; new peers accept legacy hellos without it. Names are trimmed single-line labels, limited to 40 characters / 160 UTF-8 bytes, with control characters rejected. Renaming reconnects active sessions so peers learn the new label; the device UUID and all message addresses remain unchanged. SQLite schema version 2 adds a nullable peer-name column and saves the local name in metadata. Existing stores migrate on first launch, retaining messages and receipts. Wire compatibility with older peers is tested; downgrading an upgraded app database is not supported.

## Current capabilities and next work

There are two implemented account roles: requester and shelter coordinator
(`dispatcher` in the API). Backend membership controls access. A shelter ID and its
enrolled receiving-device UUID are separate from display names and A/B/C lab roles.
A cached directory supports one enrolled receiver per shelter. Carrying another
person's encrypted request does not make it part of the carrier's personal inbox.

| Capability | Cloud available | Cloud unavailable |
|---|---|---|
| Shelter directory | Refresh authorized entries and receiving keys | Use the previously cached receiver |
| Help request | Submit one durable request ID | Save, encrypt and carry to the enrolled shelter during encounters |
| Receipt | Cloud acceptance plus staff status | Signed destination persistence receipt can return through relays |
| Speech / interpretation | Live Transcribe, editable text, Bedrock proposal | Typed fields; no offline ASR/LLM or audio relay |
| Shelter inbox | Shared authorized queue and gateway ingest | Locally received requests; cloud identity check pending |
| Inventory / staff replies | Transactional reservation, handover, release and reply history | Cached values only; no offline allocation or staff-history relay |

Remaining work: physical no-router tests on the two phones, microphone/GPS checks,
longer failure/range/energy testing, background operation, offline staff replies,
receiver/key rotation recovery, independently reviewed security, Android transport,
and a supervised always-on origin. A responder/assignment role is not implemented.
No AWS credentials are distributed in the app. No autonomous resource dispatch is
implemented or implied by an AI proposal.

Use [MORNING_DEMO.md](MORNING_DEMO.md) for the exact rehearsal and
[TEST_RESULTS.md](TEST_RESULTS.md) for actual software and physical test verdicts.
