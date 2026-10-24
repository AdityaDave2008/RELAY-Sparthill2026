# Current release — build22

Build **0.1.0 (22)** signed, archived and uploaded at **10:26:43PDT,24 October2026**.
Apple reported processing. External tester availability is **NOT VERIFIED**.
Both original development apps installed/launched22; native Mac also updated.
Existing messages, receipts, identities, keys and cloud submissions were preserved.
Next unused build:23. Builds20/21 also uploaded; their evidence is in TEST_RESULTS.

Build22 adds an optional local avatar, required name/language when saving a profile,
explicit selected personal-detail sharing at request review, a clean Help header
with small guide icon and a dedicated signed-out login screen. Medical fields remain
optional. Photo stays local. Shared text goes to authorized shelter staff and is
excluded from AI extraction; existing typed/dictated request processing is unchanged.
Update all endpoints to22 before sharing personal details. See
[resident feature/test instructions](docs/RESIDENT_SETUP.md).

Upload is not external beta approval. The original USB and paid/TestFlight bundles
retain separate data/identities. No data migration between them has occurred.
The records below are historical; this current release supersedes their next-build
numbers and current-feature descriptions.

# Previous release — build19

Build **0.1.0 (19)** signed, archived and uploaded at **07:56:48PDT,24 October2026**.
Apple reported processing. External tester availability is **NOT VERIFIED**.
Both original development phone apps were updated in place to19 and launched;
messages, receipt state, identities and earlier cloud submissions were preserved.
Next unused build:20. Build18 was an intermediate upload superseded by19.

This release improves transcript extraction, adds Medicines and editable reported
urgency, accelerates open-request replies, and fixes legacy cache timestamp refresh.
The backend also fixes same-ID direct/gateway preview races. Medicine requests go
through staff review; medicine-specific inventory is not implemented. See
[TEST_RESULTS.md](TEST_RESULTS.md) for real AWS/native UI evidence and remaining
physical wireless acceptance. The older records below are historical.

# Previous release — build17

Build **0.1.0 (17)** was signed, archived and uploaded successfully at
**05:25:17 PDT on24 October2026**. Apple reported **Uploaded package is processing**.
External tester availability/approval is **NOT VERIFIED**; the App Store Connect
browser session requires sign-in. Next unused build number:18.

Build17 includes the plain reference UI, live speech, encrypted main-form nearby
shelter requests, signed receipts and authenticated gateway ingest from16. It also
clears an obsolete connection-error label after a successful inbox refresh while
preserving unresolved queued-operation errors. See [morning demo](MORNING_DEMO.md).
The Mac and simulator were updated in place; physical phones were disconnected.
Upload is not external beta approval or a phone installation.

At07:10PDT, both original development phone apps were updated in place to17 and
launched successfully, retaining their device identities/messages/receipts. Both
now have requester setup and cached ShelterA; Mac remains the coordinator. This
local installation is independent of TestFlight approval. See TEST_RESULTS.md.

# Previous release — build16

Build **0.1.0 (16)** was signed, archived and uploaded successfully at
**04:42:55 PDT on24 October2026**. Apple reported that the package was processing.
External tester availability/approval is **not yet verified**. The browser session
is at sign-in. Upload is not approval. Next unused build number:17.

This build contains the plain reference UI, streaming speech, encrypted main-form
nearby shelter requests, signed destination receipts, authenticated gateway ingest,
and the custom API hostname. See [release evidence](docs/evidence/nearby-20261024/testflight-build16.json)
and [morning instructions](MORNING_DEMO.md).

The app uses Apple-provided CryptoKit, Security, and URLSession encryption. No
third-party cryptographic implementation is linked into the native app. The
existing `ITSAppUsesNonExemptEncryption = NO` declaration is retained for use of
Apple operating-system cryptography; [Apple's export documentation](https://developer.apple.com/help/app-store-connect/reference/app-information/export-compliance-documentation-for-encryption)
explains that category. This is not a production security or disaster-resilience claim.

The TestFlight bundle and original USB-installed bundle remain separate apps with
separate stores/identities. Do not uninstall the original app to troubleshoot an
update. Its data has not been migrated into TestFlight.

Older release records below are historical; the current build/status above takes precedence.

# Frontend redesign — build 15

Build **0.1.0 (15)** signed, archived and uploaded successfully at **02:45:16 PDT
on 2026-10-24**. It replaces decorative banners/cards and category symbols with a
flat neutral layout, typography, text tabs and a new R app icon. See DESIGN.md.
App Store Connect browser access needs a renewed sign-in; internal availability
and What to Test for15 are unverified. Upload is not external beta approval.
Next unused build:16. Older release records follow.

# UI update — build 14

Build **0.1.0 (14)** signed, archived and uploaded at **02:19:07 PDT on 2026-10-24**.
The updated interface is already installed and launched on both original development
phone apps. It adds a consistent navy/teal layout, supply choices, fixed review action,
request filters and clearer stock/voice screens. Nearby replaces the Messages tab
label; shelter conversation and transport behavior are unchanged. Next unused build:15.

App Store Connect browser sign-in expired during the availability check. Upload is confirmed; internal processing/testing availability and new What to Test notes remain unverified for14. The phones already have the development build and do not depend on this check.

The build13 records below remain historical workflow evidence.

# Current TestFlight status — build 13

Build **0.1.0 (13)** archived and uploaded successfully on 2026-10-24 at 01:47 PDT. App Store Connect subsequently showed **Testing** in the internal **RELAY Development** group (1 tester), and the new testing instructions were saved. The original development app is already installed on both owned phones; use that prepared copy for the requester/coordinator demo.

The latest build adds native account/MFA login, fixed role interfaces, editable AI preview, optional location, and stock reservation/handover/release. Read [MOBILE_TEST.md](MOBILE_TEST.md). Cloud requires an organizer-provided Cognito account; Apple/AWS-console credentials are not app credentials. A login-free nearby demo remains available.

Apple still shows that another build from version 0.1.0 is awaiting beta review, so build 13 cannot be submitted to external beta review yet. An internal Testing status does not mean the public invitation is ready for arbitrary friends or judges. The older submitted review notes describe build 2; update them for account-based cloud testing when submitting build 13 or later, including reviewer access as required.

Release archives contain no one-use debug-session importer or embedded credentials. Cloud HTTPS uses Apple system networking; local P2P remains plaintext. Future archives must use an unused build number (next is **14**). Build 13 is already uploaded and must not be uploaded again.

The entries below are historical setup records; their version numbers and screen descriptions are superseded by this section.

# RELAY teammate beta deployment

**Latest upload: 0.1.0 (9)** bundles the temporary HTTPS demo API address and adds validated WAV import for voice testing. Both original phone apps installed and launched build 9 with all data preserved. Archive/upload passed at 00:32:50 PDT on Oct 24; Apple processing completed and RELAY Development explicitly shows build 9 Testing; build-specific test notes are saved. External build 2 remains Waiting for Review; this upload does not imply external approval. Mobile cloud login/voice is not yet an end-to-end verified feature. [Demo instructions](DEMO_HOSTING.md), [release evidence](evidence/testflight-upload-build-9.json).

**Previous upload: 0.1.0 (7)** adds reversible shelter removal/restoration and a visible import flow with receiver preview. Apple accepted the signed upload at **23:12:02 PDT on 2026-10-23**. Processing completed; **RELAY Development shows Testing** for build 7. What to Test notes are saved. The external group still has build 2 Waiting for Review, so this internal update is not public-link approval. Both original development phone apps are installed and launched on build 7 with all 24/23 stored envelopes, receipts, shelters and identities preserved. The separate paid-bundle copy on the first phone was left intact. [Release evidence](evidence/testflight-upload-build-7.json), [installation checks](evidence/physical-build7-install.json).

**Previous upload: 0.1.0 (6)** adds Help, Requests, Shelters and Messages; saved shelter codes, durable help drafts, review before submission, a local device inbox and separate delivery receipts. Signed archive and signature verification passed; Apple accepted the upload at **22:36:23 PDT on 2026-10-23**. Apple processing completed; **RELAY Development shows Testing** for build 6, and its What to Test notes are saved. At the release check, the internal group had one tester listed as Invited. Build 2 remains the external submission, Waiting for Review. Both original development phone apps were subsequently updated/launched as build 6 at approximately 22:57 PDT, retaining their identities and messages. The first phone also has a separate paid-bundle build 6 installed. [Build 6 release evidence](evidence/testflight-upload-build-6.json), [direct installation evidence](evidence/physical-build6-install.json).

**Previous update: 0.1.0 (5)** adds editable persistent device names, clearer destination labels, advanced-only test roles, and forwarding copies without payload previews. Signed archive/upload passed at 19:37:57 PDT. Apple processing completed; RELAY Development shows **Testing** and build-specific test notes are saved. Both phones have the direct build installed; iPhone 16 launched, iPhone 15 Pro Max is locked and must be opened. External build 2 remains Waiting for Review; it was not replaced. [Build 5 evidence](evidence/testflight-upload-build-5.json).

**Previous update: 0.1.0 (4)** contains the chat UI and repeat-send fix. It is directly installed/launched on both physical iPhones with their original IDs and all stored messages preserved. Paid-team upload succeeded at 19:18:26 PDT. Apple processing completed; RELAY Development shows **Testing** for build 4 and its test notes are saved. See [release evidence](evidence/testflight-upload-build-4.json). External build 2 was not canceled/replaced.

**Previous update: 0.1.0 (3)** is uploaded, processed, and verified **Testing** in RELAY Development. It contains the redesigned Messages/Nearby/Tools UI, reply action, clearer receipt progress, validation, templates, identity sharing, and improved keyboard dismissal. Build-specific test notes are saved. The original external submission below is build 2; it was not canceled or replaced. [Build 3 release evidence](evidence/testflight-upload-build-3.json).

Direct installation and launch of build 3 succeeded on both the iPhone 15 Pro Max and iPhone 16 using the original Personal Team bundle ID, preserving both device UUIDs and stores. TestFlight installations use the separate paid-team identifier.

Status (2026-10-23 PDT): **version 0.1.0 (2) was signed and uploaded successfully** at 18:18:46 PDT. The keyboard fix is included. Processing is complete and the external build status is **Waiting for Review**. Public link: **https://testflight.apple.com/join/paGggTvE** (100-tester limit). Apple explicitly says testers cannot join until the group has an approved build; approval and actual installation are not yet verified. Physical offline acceptance remains separate in TEST_RESULTS.md.

## Publishing account and app record

- Enrolled team: **U4G9LV39GM**, RELAY demo developer, using the user-selected `anonymousfool` account already signed into Xcode. The user accepted Apple's updated Developer Program agreement and membership resources became available.
- App: **RELAY Offline Lab**, Apple ID **6826458231**, SKU `relay-offline-ios`, English (U.S.), iOS.
- [App Store Connect / TestFlight](https://appstoreconnect.apple.com/teams/REDACTED-ID-f6578ae3d61e/apps/6826458231/testflight).
- Registered distribution bundle ID: **com.nikilthalapaneni.relay**. Apple rejected `org.relay.prototype.ios` as unavailable under this team. The original Personal Team phone installs are untouched; the new identifier has a separate store/device UUID when installed.
- Initial signed archive was blocked because the paid team had no development devices. Registered the previously verified Sender A iPhone 15 Pro Max; retry produced a signed release archive and valid local signature. No phone was reconnected or reinstalled for this publishing step.
- Signed archive: `/tmp/RELAY-testflight.q944Ku/RELAY.xcarchive`. Export/upload succeeded using automatic App Store Connect signing. [Archive log](evidence/archive-testflight-build-2.txt), [upload log](evidence/testflight-upload-build-2.txt), [sanitized release record](evidence/testflight-upload-build-2.json).
- Beta description/review instructions are saved without claims of verified offline wireless operation. User explicitly approved account contact details for Apple's beta reviewers; those private details are not stored in this repo.
- Internal group **RELAY Development** was created with automatic build distribution enabled as the prerequisite for external testing. External group **RELAY Teammates** contains build 0.1.0 (2), submitted for beta review with automatic tester notification selected. The public link is configured but blocked pending an approved build. No teammates have been granted App Store Connect account roles or sent individual email invitations.

## Local readiness

- iOS/macOS targets share the existing tested relay engine.
- App icon assets are included. Regenerate with `xcrun swift scripts/generate_app_icon.swift .` from RELAY, then `python3 scripts/generate_project.py` if project structure changes.
- The current installed iPhone build uses the free Personal Team for direct device testing. TestFlight needs the user's enrolled Developer Program team; do not assume the Personal Team is that membership.
- The iOS project now uses `com.nikilthalapaneni.relay` and the enrolled signing team. The original `org.relay.prototype.ios` phone apps remain available for earlier test data.
- The selected Xcode 26.1.1 / iOS 26.1 SDK meets Apple's published October 2026 upload SDK minimum (Xcode 26 and iOS 26 SDK); no large Xcode update is indicated by that requirement. Recheck at submission time: https://developer.apple.com/news/upcoming-requirements/.
- Latest source version is **0.1.0 (7)**. The shelter workflow passed 35 core tests and native Mac Remove/Restore/import UI checks. Build 7 is directly installed/launched on both original physical phone apps, with IDs and stored messages preserved. Controlled physical wireless acceptance remains separate.
- `ITSAppUsesNonExemptEncryption = NO` is generated for iOS. Source review found plain Network.framework TCP, no TLS/custom encryption, and no third-party libraries. This matches [Apple's key guidance](https://developer.apple.com/documentation/bundleresources/information-property-list/itsappusesnonexemptencryption). Reassess before introducing encryption; this setting does not make the prototype confidential.

## Repeatable archive/upload

Use the enrolled account already signed into Xcode; agreement acceptance, bundle registration, app creation, and the first upload are complete. No phone needs to be attached for this step. From `RELAY/`:

```sh
# Set to the identifier actually registered under the enrolled team.
export RELAY_TEAM_ID=U4G9LV39GM
export RELAY_BUNDLE_ID=com.nikilthalapaneni.relay
bash scripts/testflight.sh 17          # next unused build: signed archive only
bash scripts/testflight.sh 17 --upload # next unused build: archive and upload
```

The script stores logs/archives in a fresh `/tmp/RELAY-testflight.*` directory, outside the file-provider-backed source directory. It uses automatic signing and never accepts a password/token. The script's signed archive path passed; its export/upload command was executed separately against that archive and passed. Use the next unused build number after each upload; the script does not silently change it. Check Apple's processing/review state after upload.

TestFlight delivers installed builds, not live source changes. Each future fix needs a new build/upload, then testers install its update (or enable TestFlight automatic updates). Downloading needs internet; the subsequent RELAY radio test can be offline. External testing still requires Apple's beta-review eligibility/approval.

## Immediate testing while external review is pending

The existing enrolled account holder was added to **RELAY Development**. App Store Connect verifies **1 Tester**, status **Invited**, and build **0.1.0 (2): Ready to Test**. Open Apple's invitation in the developer account inbox on the iPhone, install TestFlight, and accept/install RELAY Offline Lab. Inbox delivery, invitation acceptance, and phone installation have not yet been observed. This internal route does not wait for external beta review and does not require USB. No teammate developer-account roles were created or expanded.

## Teammate rollout steps

1. **Completed:** paid-team signing, upload, Apple processing, beta metadata, testing groups, and external review submission. Build 0.1.0 (2) is **Waiting for Review**.
2. **Apple approval pending:** the [public TestFlight invitation](https://testflight.apple.com/join/paGggTvE) exists, but Apple says testers cannot join until this group has an approved build. It is open to anyone with the link, capped at 100 testers. No teammate account role, device UDID, or USB setup is needed for external TestFlight.
3. Once approved, install Apple's TestFlight app on each iPhone, open the invitation link, accept the beta invitation, and install RELAY Offline Lab. Enable TestFlight automatic updates if desired. Keep internet available for installation and updates.
4. This is a different bundle ID from the original development app. Use the TestFlight copy consistently, record its new device UUID on each phone, choose roles again, and preserve the old installation until test evidence is exported.
5. Run the actual offline radio test with cellular off, no conventional Wi-Fi association/hotspot, Wi-Fi/Bluetooth radios enabled, no USB/tethering, and both apps foreground. Follow TEST_PLAN.md for the separate A–B, B–C, and B–A encounters and Mac setup.

Apple references: [TestFlight overview](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/), [external testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers/), [distribution preparation](https://developer.apple.com/documentation/xcode/preparing-your-app-for-distribution).

## Submitted beta description

RELAY is an engineering prototype for testing local message exchange and store-carry-forward delivery between Apple devices. It uses nearby discovery, a durable local message queue, duplicate suppression, and delivery receipts. Test only with synthetic messages. Keep the app foreground during encounters. This beta is not an emergency service and does not provide authenticated identities or confidential messaging. Physical infrastructure-independent delivery has not yet been verified.

## Submitted “What to Test”

Build 0.1.0 (2): verify that Done at the top right dismisses the keyboard from both destination and message fields.

Use synthetic messages only. Keep RELAY foreground and awake. Allow Local Network access. For offline trials, turn off cellular, disconnect USB and ordinary Wi-Fi networks/hotspots, but keep Wi-Fi and Bluetooth radios enabled.

Direct test: start discovery on two iPhones, choose the nearby peer as destination, and verify the request and receipt persist. Relay test: select Sender A, Relay B, Receiver C, copy C's UUID to A, transfer A to B, stop A, terminate/relaunch B, then let B encounter C. Later reconnect B to A and verify the separate final delivery receipt.

Use the retransmit and interrupted-transfer controls. Record actual message IDs, duplicate suppression, restart recovery, connection changes, and radio/SSID conditions. A common-router connection or a logical A-B-C route is not proof of infrastructure-independent wireless delivery. Physical acceptance is still being evaluated; this is not an emergency service.

## Submitted beta review notes

No account login is required inside RELAY. Peer communication requires another copy of RELAY on a nearby compatible Apple device and Local Network permission. Keep Wi-Fi and Bluetooth radios enabled. A single device can display its persistent identity, save an addressed synthetic request while offline, and retain the queue across app restart. Tap Done at the top right to dismiss the keyboard.

For direct transfer, select Relay B on both iPhones, start nearby discovery on both, select the discovered peer as the destination, and send synthetic text. To test store-carry-forward, use three devices assigned Sender A, Relay B, and Receiver C. Enter C's displayed UUID as A's destination. Transfer A to B, stop A, terminate and relaunch B, start discovery on B and C, then verify C receives the queued request. Return the receipt through a separate B to A encounter. Roles are testing controls; forced routing does not prove physical separation.

This foreground engineering beta uses plaintext, unauthenticated local TCP and synthetic test data. It has no backend, purchases, or external login. Offline wireless acceptance and disaster resilience are not claimed.

External TestFlight builds expire after 90 days; this is a beta distribution route, not permanent emergency deployment.
