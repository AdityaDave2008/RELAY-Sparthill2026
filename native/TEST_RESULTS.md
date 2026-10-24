# RELAY test results — updated 24 October 2026

**Current verdict:** the15ProMax now has development build23 for first-run replay;
the iPhone16 and running Mac remain on build22. All three retain the build22 feature set. Incident alerts downloaded and persisted on both physical phones. Native
software, real AWS services and separate-encounter relay controls pass. Physical
router-free wireless acceptance is still **NOT TESTED**. The older dated sections
below are historical; this checkpoint supersedes their feature/release status.

## Development build23 — replay personal-details setup

24October2026,10:43–10:46PDT. Added an explicit DEBUG launch argument that resets
only the current resident account's two onboarding-completion flags. Existing login,
Keychain profile, device identity, requests and receipts remain intact. No account
creation/reset, schema or transport change. Same hardware/SDK as build22.

All three native builds PASS. Simulator UI replay displayed **A little about you**
with retained synthetic photo/fields; Skip→guide→Skip and normal restart returned
home without replay. Original15ProMax installed23 and launched; final readback
confirms both onboarding flagsfalse, previous53messages and all prior immutable
submissions/receipts/keys/identity retained, quick_checkok. Initial replay readback
was still completed; same demo session restoration and direct launch argument fixed
the final setup. Physical screen appearance remains user-observed; no capture made.

No TestFlight23 upload; iPhone16 and running Mac remain22. Core/backend unchanged,
so prior84Swift/111backend run was not repeated. Shell syntax and native builds
validated; physical radio acceptance remains NOT TESTED.
[Evidence](docs/evidence/build23) · [Repeat command](docs/RESIDENT_SETUP.md#replay-the-first-run-demo--development-build23).

## Fresh resident demonstration setup —24October2026,10:33PDT

Created one new synthetic Cognito resident with MFA preserved, requester-only
ShelterA membership and no outgoing email. Existing10memberships retained;11total.
Public authentication/directory/history checks passed; new request history was empty.
Reloaded only API as30322; worker27162/tunnel12053 retained. Public preflight PASS.

Preloaded the original iPhone15ProMax build22 through its existing DEBUG one-use
session importer and relaunched it. The import file was consumed; its new account
scope cached ShelterA and receiving keys, with zero local requests. Existing53
messages, prior receipts, cloud submissions, device ID and keys preserved; SQLite
quick_check=ok. Mac and iPhone16 accounts were unchanged. Welcome Skip steps and
physical voice/demo execution are still operator actions, not claimed tests.

Read-only stock check: ShelterA water packs on_hand1/reserved0/available1; other
stock0. Created no requests, AI calls or inventory mutations for preparation.
Accounts/credentials remain private outside Git. See [two-minute script](MORNING_DEMO.md#fast-resident-presentation--about-two-minutes)
and [sanitized evidence](docs/evidence/resident-demo-20261024).

## Build22 — local avatar, selected profile sharing and cleaner home/login

24 October2026, approximately10:00–10:28PDT. Mac M3Pro/macOS26.6.2(25G83),
Xcode26.1.1(17B100), iOS/macOS26.1 SDKs. Physical iPhone15ProMax/iOS27.0.1(24A446)
and iPhone16/iOS26.2(23C55) were available, signed, installed and launched. Simulator:
iPhone17Pro/iOS26.1. Internet remained available; no physical path exclusion.

| Check | Result | Evidence / boundary |
|---|---|---|
| Swift tests | PASS |84 tests, zero failures; required basics/legacy profile decoding/photo bounds/GPS metadata removal/selective snapshot/encryption/restart/immutable retry |
| Backend tests | PASS |111 tests, one testclient deprecation warning; authorized snapshot reads, unrelated requester/staff404, changed retry409, old nil-profile retry, gateway/direct dedup, profile exclusion from model prompt |
| Builds | PASS | Signed original iOS, paid-bundle Simulator, native Mac and distribution archive |
| Home layout | PASS (Simulator UI) | Ask for help first, small guide icon, no Your details link or delivery banner; emojis/readable labels retained |
| Profile/photo | PASS (Simulator UI + Keychain) | Required-language validation, user selected synthetic avatar in native picker, Save→terminate/relaunch→reopen retained photo/language/old fields |
| Selected sharing | PASS (native live flow) | Review defaults off, basic selection excludes health; selecting health/support shows exact snapshot; photo absent |
| Shelter receipt | PASS (online software control) | Request `REDACTED-ID-428038d0b0e7` displayed selected synthetic profile on Mac; resident showed signed shelter receipt and cloud acceptance separately; one persistent record on each |
| Login UI | PASS (Simulator) | Sign-out replaced workspace with dedicated email/password screen; same existing account restored through DEBUG importer, profile/photo/history retained. New password/MFA entry not rerun |
| Phone update | PASS | Both original apps installed/launched22; versions confirmed with devicectl |
| Upgrade preservation | PASS |15ProMax51→51 messages/51→51 cloud records;16:51→51 messages/46→46 cloud records, sampled before synthetic live request. IDs, keys, message bodies, previous receipts and immutable submissions unchanged; quick_check=ok |
| TCP control | PASS | Loopback interruption/no false ACK, retry/dedup, carrier restart/separate encounters/return receipt; original ID `REDACTED-ID-67de81ee1015`, receipt `REDACTED-ID-f8baee50b905` |
| Live service preflight | PASS | Public HTTPS/authorized staff/directory/account guard, anonymous401, no-store, one worker;36/100 request allocations,12/20 transcription allocations |
| TestFlight | PASS (upload only) | Build22 upload completed10:26:43PDT; Apple reported processing; external approval/availability NOT VERIFIED |
| Physical radio A–E | NOT TESTED | No new infrastructure-independent/direct/separate-range/return-receipt/failure-reliability measurement |
| Remaining manual checks | NOT TESTED | Real-phone photo entry, largest text/VoiceOver, clearing a disposable profile, unavailable Keychain/iCloud-only image and same-device account isolation |

Display name and language are required to save a profile; first-run Skip still
allows urgent help without completing setup. Health/photo remain optional. Photo
stays local. Explicitly selected text is a frozen request attachment, stored in the
request database and cloud and encrypted inside the nearby envelope. Attached
profile fields are excluded from the model prompt; typed/dictated request text
still goes through the existing AI workflow. Editing local details cannot erase a
sent snapshot. Update endpoints to22 before sharing; old clients do not preserve
this new optional field in their typed caches. See [resident contract](docs/RESIDENT_SETUP.md).

The first new Swift persistence test failed because its fixture used an invalid
scope string; corrected to the required64-character hash and reran all84 successfully.
Python imports stalled on the file-provider-backed environment. Created a temporary
venv outside Documents, installed the existing requirements.lock, copied source,
and ran111 tests there. No dependency list changed. The same locked environment
now runs API27161/worker27162 against current source; tunnel12053 and private config
were retained, including all10 account memberships. These processes and Mac internet
remain dependencies; this is not a managed-compute deployment.

Evidence: [build22 logs and sanitized observations](docs/evidence/build22).
No credentials, device databases or real medical data are in those artifacts.
Physical claims remain separate: direct offline P2P, three-device physical carrying,
bidirectional physical delivery, router-independent path and repeated-failure
reliability are all **NOT VERIFIED** by this update.

## Build21 — supply emojis, private resident details and walkthrough

24 October2026, approximately09:41–09:49PDT. Same hardware/SDK versions as build20
below. Internet was available. This update changes the native apps/shared local
models; no backend request schema, inference prompt or radio protocol changed.

| Check | Result | Evidence / boundary |
|---|---|---|
| Swift tests | PASS | 78 tests, zero failures; optional profile/validation/locale, serialization, per-account setup persistence and protocol-label compatibility added |
| Native builds | PASS | macOS, signed original-bundle iOS, iOS Simulator; source manifest matches final source snapshot |
| First-run setup | PASS (Simulator UI) | Existing requester account on first feature launch saw optional profile; synthetic fields saved; transitioned to six-page walkthrough |
| Profile persistence | PASS (Simulator Keychain) | App terminated, updated and relaunched; profile retained all nine synthetic fields, including O− and numeric measurements; introduction did not repeat |
| Cancel edits | PASS (Simulator UI) | Changed synthetic name, cancelled, reopened; original saved value retained |
| Walkthrough | PASS (Simulator UI) | All six pages traversed; Back verified; completion returned home; top How RELAY works reopened page1 with Close |
| Profile data boundary | PASS (code + storage check) | No automatic request/AI attachment exists. Synthetic name/health-note markers absent from Simulator request SQLite/WAL/SHM; setup metadata contains only two booleans |
| Emojis/layout | PASS (native visual control) | Resident supply buttons retain readable labels with emojis; Mac inventory headings show matching emojis; height/weight units remain in field labels |
| Coordinator workspace | PASS | Mac opened Inbox directly with existing coordinator account; no resident introduction; inventory read without stock changes |
| Physical installs/launches | PASS | Both original apps installed/launched as21, devicectl verifies build; no personal/medical fields populated on physical phones by the agent |
| Upgrade preservation | PASS |15ProMax51→51 messages,51→51 cloud records;16:51→51 messages,46→46 cloud records. Device IDs, keys, message bytes, prior receipts and immutable cloud submissions retained; quick_check=ok |
| TCP regression | PASS | Frame interruption/no false ACK, duplicate suppression, carrier restart, separate encounters and reverse receipt on loopback |
| TestFlight | PASS (upload only) | Paid build21 upload succeeded09:47:27PDT; Apple said processing. External availability/review remains NOT VERIFIED |
| Backend regression | NOT RERUN | No backend source changes in this update; last build20 run was106 tests. Read-only live preflight passed after the separate account task's runtime reload |
| Additional manual UI checks | NOT TESTED | Physical profile entry, first-run Skip branches, largest text/VoiceOver, same-device account switching, clearing profile, locked-Keychain failure and offline profile editing require further manual checks |
| Physical radio acceptance A–E | NOT TESTED | No router exclusion/range/failure-reliability measurement was performed |

Personal details are optional, self-reported and local to that account/device in
Keychain (`WhenUnlockedThisDeviceOnly`, sync disabled). They are **not attached to
requests or sent to AI** in this version. The SQLite first-run flags are separate
from medical fields. There is no new public sign-up or medical triage feature.
See [resident setup behavior](docs/RESIDENT_SETUP.md) and
[build21 evidence](docs/evidence/build21). Simulator UI capture occasionally failed;
reacquiring the native surface allowed final state verification. No failed capture
was counted as successful UI verification.

The separately running AWS account task reported adding six memberships while
preserving the previous four and reloading API as19133; worker12407 and tunnel12053
were retained. This native task did not edit memberships, credentials, quotas or
the backend process configuration. The public hostname remains relay.stepcheck.app.

## Build20 — alerts, shelter instructions/distance and location requirement

24 October2026, approximately09:10–09:18PDT. Mac: M3 Pro, macOS26.6.2(25G83),
Xcode26.1.1(17B100), iOS/macOS26.1 SDKs. Phones: iPhone15ProMax/iOS27.0.1(24A446)
and iPhone16/iOS26.2(23C55). Simulator: iPhone17Pro/iOS26.1. Internet was available;
no physical router exclusion, cellular-off, range or isolated-radio test was run.

| Check | Result | Actual evidence / boundary |
|---|---|---|
| Swift core | PASS | 71 tests, zero failures |
| Backend | PASS | 106 tests, one testclient dependency deprecation warning |
| Native builds | PASS | macOS, signed original-bundle iOS and iOS Simulator; source hashes retained |
| Real incident publication | PASS | Mac UI published `REDACTED-ID-a82ea2f9709f`, title `DEMO ONLY · Shelter A update`; resident simulator displayed it and cleared NEW on opening |
| Both physical phone caches | PASS | Both post-install SQLite stores contain that same announcement ID and withdrawn API-test ID |
| Live retry/auth/withdrawal | PASS | `REDACTED-ID-eec2792d2c62`; one logical notice after retry, both separate requester accounts saw it, resident publishing403, both saw revision2 withdrawal |
| Cache without cloud | PASS (simulated isolation) | Paused cloud in Simulator, restarted app; notice and read state remained, Refresh disabled. Restored normal cloud mode afterward |
| Shelter editing and distance | PASS (synthetic location) | Mac UI published fictional address/instructions and1.23456,2.35567. Simulator at1.23456,2.34567 displayed `About 1.1 km away` with straight-line/accuracy/time label. Cleared synthetic metadata afterward, revision2 |
| Location required in current composer | PASS | Empty snapshot + empty landmark disabled Send with a clear error. Typed `Fictional Demo Hall, room12` enabled Send without GPS. Test draft not submitted, then cleared |
| Read-aloud controls | PASS (Simulator UI) | Final build's Listen→Stop reading→Listen transitions; start/stop exercised. Human-audible physical output and installed voices in airplane mode remain NOT TESTED |
| Upgrade preservation | PASS |15ProMax51→51 messages,51→51 cloud records;16:51→51 messages,46→46 cloud records. Original IDs/bodies/receipt state/cloud submissions/device keys retained; both SQLite quick_check=ok |
| Phone install/launch | PASS | Both original `org.relay.prototype.ios` apps updated and launched with devicectl; build20 confirmed. Separate resident accounts retained |
| Mac coordinator | PASS | Same store/receiver identity, existing coordinator test session restored via DEBUG one-use importer; latest build launched |
| TCP controls | PASS | Interrupted frame/no false ACK, retries, duplicate suppression, separate A→B→C encounters and C→B→A receipt across carrier SIGKILL/restarts; loopback only |
| TestFlight upload | PASS | Paid `com.nikilthalapaneni.relay` build20 upload succeeded09:15:52PDT; Apple said processing. External availability/review NOT VERIFIED |
| Physical acceptance A–E | NOT TESTED | No new evidence of infrastructure-independent radios, physical out-of-range relay, or measured repeated-failure reliability |

Live publish + identical retry took1.270s combined in one synthetic API sample.
This is not a latency guarantee or a wireless measurement. Alert fetch is a
foreground periodic HTTPS pull (about12s, delayed by other async work), not push.
Expiry and withdrawals are distinct; an offline phone cannot learn a later
withdrawal until it refreshes. New announcements are not carried by P2P in build20.

Hosting recovery: the prior Quick Tunnel process had exited; public health
returned Cloudflare1033. Restarted the tunnel detached and updated only the existing
CloudFront origin to `computation-disc-copies-improvement.trycloudflare.com`.
The app URL remains `https://relay.stepcheck.app`. API12406/worker12407 use the
existing approved AWS demo18 config; tunnel12053. Final preflight verifies HTTPS
health, correct dispatcher identity, authorized directory, anonymous401 and AWS
account/budgets. The Mac, temporary tunnel and workshop session remain dependencies.
No IAM expansion, managed-compute deployment or new Namecheap domain was performed.

Evidence: [build20 artifacts](docs/evidence/build20), including actual test logs,
live IDs/timing, source manifest, phone-preservation counts and build status.
Raw credential/session files and device databases remain private outside the repo.
See [feature contract and identity explanation](cloud/docs/ANNOUNCEMENTS.md).
Public self-registration/invitations are still absent; each demo person must be
provisioned a distinct enrolled Cognito account. Location requirements apply to
the new native composer, while old persisted submissions remain byte-compatible.

## Build19 — extraction, urgency, medicine requests and faster replies

24 October2026, approximately08:00PDT. Actual pipeline is AWS Transcribe → Bedrock
Nova Lite (`amazon.nova-lite-v1:0`) → field validation → editable native request.
The API and ordinary worker still run on this Mac behind `relay.stepcheck.app`.

Changes and observed causes:

- Global number/negation heuristics treated people, age and room numbers as competing
  supply quantities and “no internet” as request negation. Grounding now separates
  resource counts, people, landmarks and explicit urgency. Known fields are retained
  when other details require review; requested units are editable and not silently
  converted into stock units.
- A real Nova result contained correct fields but an unexpected `missing_fields`
  entry (`urgency_evidence`). This originally discarded the whole proposal. The
  extraction call now requests the named structured tool, validates its input, and
  derives missing-field annotations. Unexpected tools are never executed. Two
  synthetic direct Bedrock diagnostic calls ran outside the app allocation counter.
- A bounded one-slot preview lane starts durable queued previews promptly, sharing
  the same conditional lease with the ordinary worker. Client checks every500ms
  while extracting, with an explicit manual-entry escape. Model output is not an
  inventory decision or medical triage.
- Open requests fetch one authorized batched snapshot about every3s; inboxes refresh
  about every8s and directory setup about every60s. Background reads preserve newer
  replies and pending writes. This is foreground polling, not push notifications.
- Legacy caches truncate fractional server timestamps. Comparing the persisted
  timestamp representation fixes an inbox-stopping mismatch while retaining the
  original submission. Changed immutable content still fails validation.
- A simultaneous direct/gateway submission could see the preview already bound to
  the SAME request and incorrectly reject it. Same-ID races now resolve through
  the existing atomic transaction/replay check. Reuse for another request ID still
  fails; no second model call or stock allocation is allowed.

New UI: Medicines category, editable medicine name/details, requested units, and
Routine / Soon / Urgent / Immediate tags plus “not specified.” AI suggests urgency
only from stated language; the person can override or clear it. Tags/details travel
inside the encrypted request and appear in the shelter inbox/review. Medicines are
staff-reviewed requests; medication-specific inventory, prescribing, dose calculation
and substitution are NOT implemented. Water/food/blanket stock remains separate.

Validation:

- **66 Swift tests PASS** ([log](docs/evidence/build19/relay19-swift-tests.txt)),
  including new fields across encrypted carrier restart/receipt, legacy decode,
  persisted manual tags, out-of-order replies, pending-action preservation and
  fractional timestamps without accepting changed content.
- **99 backend tests PASS** ([log](docs/evidence/build19/relay19-backend-tests.txt));
  one existing dependency warning. New coverage includes narrative counts,
  no-internet negation, ungrounded urgency/location, medicine strengths versus item
  counts, legacy immutable digests, snapshot authorization, one-call preview leases
  and the direct/gateway preview race.
- **Loopback TCP PASS** ([log](docs/evidence/build19/relay19-tcp-test.txt)); restart,
  interrupted frame, retry, duplicate and reverse-receipt controls. Not wireless.
- **Real AWS/public API PASS:** three synthetic preview cases matched expected
  fields in3.498s,3.203s,2.265s. Narrative case: water2/people4/room12/Urgent;
  medicine case: inhalers2/people3/Immediate; missing-count case kept quantity unknown.
  Two coordinator reply POST+snapshot-read samples took1.171s/1.211s. These are
  individual API observations, not guaranteed UI latency or a load benchmark.
  [Evidence](docs/evidence/build19/relay18-live-evidence.json).
- **Native UI PASS:** actual simulator extraction, manual Urgent→Soon override,
  review/send, matching Mac inbox tag, medicine details/staff-review screen, and a
  Mac reply appearing in the open requester detail without manual refresh after
  sending. Request `REDACTED-ID-a90234153072` reconciled cloud/nearby
  and recognized a destination receipt. Internet remained available.
  [Record](docs/evidence/build19/relay19-ui-evidence.json).
- **Build/install PASS:** Mac, simulator, signed original iOS build and TestFlight
  archive/upload. Build19 uploaded07:56:48PDT; Apple processing, external availability
  unverified. Both physical phone apps report19 and launched. All pre-update UUIDs,
  messages/receipts and immutable cloud submissions were preserved:45 messages/47
  cloud records on15ProMax,47 messages/46 cloud records on16. Both retain requester
  accounts. [15](docs/evidence/build19/iphone15-installation.json),
  [16](docs/evidence/build19/iphone16-installation.json),
  [build markers](docs/evidence/build19/build-markers.txt).
- Final read-only cloud preflight **PASS**, counters34/100 request/preview allocations
  and10/20 transcription allocations at capture. No new audio test was necessary
  for these extraction changes. Streaming remains implemented; phone microphone
  quality and physical no-router A–E acceptance are not established by this session.

## Physical installation follow-up — 07:10 PDT, 24 October

Both original development apps (`org.relay.prototype.ios`) were updated in place
from15 to17. Device-reported build17 and actual launches **PASS** on both iPhone15
ProMax and iPhone16. SQLite quick checks passed. Every pre-update message body,
existing final receipt, device UUID and immutable cloud submission was retained:
38 prior messages/23 cloud records on15ProMax;39 prior messages/20 cloud records
on16. The15ProMax later held39 envelopes after normal nearby activity; this is not
controlled offline evidence. Raw stores and keys remain outside Git.

The15ProMax keeps RequesterA. The16 was prepared as existing RequesterB for the
user's two-requester/Mac-shelter demo; its former coordinator history remains
stored in its earlier account scope. A refreshed session was verified against the
API, imported through the DEBUG-only one-use file into Keychain, and the file's
removal was confirmed. Both phones cached ShelterA and its enrolled receiving keys.
No credentials were embedded in the build or committed.

[15ProMax preservation](docs/evidence/phone-build17-20261024/iphone15promax.json),
[iPhone16 preservation](docs/evidence/phone-build17-20261024/iphone16.json),
[cloud preflight](docs/evidence/phone-build17-20261024/cloud-preflight.json).
Phone microphone/GPS, visual acceptance and controlled no-router A–E tests remain
**NOT TESTED** by this installation step. Cloud counters remained24/100 and8/20.

## Final overnight checkpoint — builds16/17

- **Builds PASS:** macOS, iOS Simulator, signed iOS archive and Apple upload.
  Build16 uploaded04:42:55PDT; build17 uploaded05:25:17PDT and fixes an old network
  error remaining after a successful inbox refresh. Apple reported processing;
  external TestFlight availability/approval is **NOT VERIFIED**.
- **62 Swift tests PASS**, including serialization, persistence/restart, duplicate
  suppression, TTL/hops, inventory exchange, interrupted retry, encrypted envelopes,
  signed receipts, tampering, durable device keys and late-state projection.
  [Full core test log](docs/evidence/nearby-20261024/relay-isolated-core-tests.txt).
  Fresh isolated scratch storage avoided file-provider build-cache timestamp errors.
- **87 backend tests PASS**, with one dependency deprecation warning. Includes
  enrolled-device ownership, shelter receiver revision, exact-byte signature checks,
  authorization and direct/gateway deduplication.
  [Backend log](docs/evidence/nearby-20261024/relay-nearby-backend-all.txt).
  The final build17 change is confined to native UI error recovery/build numbering;
  the tested shared core and backend sources did not change afterward.
- **Native UI PASS:** plain reference theme, requester/coordinator navigation,
  text sizes/high contrast, keyboard dismissal, review/send, request status and
  inventory. Final build17 launched on Mac and iPhone17Pro simulator in place,
  retaining saved messages and account/device identity. No physical installation
  occurred in this final session; both paired phones were disconnected.
- **Real online workflow PASS:** request `REDACTED-ID-9f9e777b271a`
  went from simulator form/Bedrock to Mac approval/reservation and recorded handover.
  Synthetic water stock changed10→8 on hand, with0 reserved after fulfillment.
  This records a synthetic ledger action, not physical resource delivery.
  [UI rehearsal](docs/evidence/streaming-20261024/relay-ui-cloud-rehearsal.json).

### Actual encrypted native encounter evidence

Two native iPhone simulators and the native Mac used Bonjour/Network.framework on
one host. Internet remained available to the host. Requester cloud delivery was
paused explicitly; this is application route isolation, not radio isolation.

1. Direct nearby/gateway test: request `REDACTED-ID-453c2f5043dd`,
   signed receipt `REDACTED-ID-4c72bed4f187`. Mac decrypted and
   persisted it, then ingested it under the original requester. Carrier records
   excluded it from their personal cloud inbox. Wire payload did not expose text
   or the explicitly synthetic coordinates1.23456,2.34567.
   [Evidence](docs/evidence/nearby-20261024/relay-native-nearby-evidence.json).
2. Separate encounters: request `REDACTED-ID-0ac5b204e3a8` was
   persisted at B while C was quit. B was terminated/relaunched. With A terminated,
   B forwarded to C at hop2; C created receipt
   `REDACTED-ID-0b5f91e4b72a`. C was quit; B was restarted again;
   A received the returning receipt at hop2. A/C never ran together during this
   sequence. Resuming source cloud reconciled the same request ID.
   [Snapshots and actual logs](docs/evidence/nearby-20261024/1792841365.json).
3. Controlled repeated failures: **3/3 loopback TCP trials PASS**, each with a
   truncated frame, retry, duplicate suppression, two actual carrier-process
   crashes/restarts and a reverse receipt. Trial durations1.360/0.979/0.932s are
   whole software-test durations, not wireless latency or reliability estimates.
   [IDs and results](docs/evidence/nearby-20261024/repeated-tcp-controls.json).

Selected native logs (same-host software evidence):

```
11:21:16Z A STORAGE_ACK_RECEIVED id=REDACTED-ID-0ac5b204e3a8 kind=RELAY_STORED ack_latency_ms=40
11:21:55Z C PERSISTED id=REDACTED-ID-0ac5b204e3a8 hops=2
11:21:55Z C RECEIPT_CREATED id=REDACTED-ID-0b5f91e4b72a original=REDACTED-ID-0ac5b204e3a8
11:23:57Z A FINAL_RECEIPT_RECOGNIZED id=REDACTED-ID-0b5f91e4b72a original=REDACTED-ID-0ac5b204e3a8
```

### AWS, domain and recovery evidence

`https://relay.stepcheck.app` is verified TLS through Namecheap DNS / CloudFront /
the existing HTTPS Quick Tunnel to this Mac. It forwards authorization/WebSockets
and does not cache the API. No PC or managed compute deployment is claimed.

Final preflight initially **FAILED503**: AWS workshop refresh credentials expired.
The existing workshop session was renewed for the same account928489693154 and
WSParticipantRole/Participant; API/worker restarted without resetting queues or
budgets. Preflight, real live speech and real Bedrock processing then **PASSED**.
This failure is evidence for running preflight shortly before presenting.

- Renewed live stream `REDACTED-ID-9100359cfc3d`: synthetic1.824s
  WAV through native Swift/custom-domain WSS, ready991ms, first partial2145ms,
  durable completion3857ms. Same-ID replay returned the saved result. “Shelter A”
  was misheard as “Sheltering”; transcript review remains required. This is one
  sample, not a noisy-speech/phone-microphone benchmark.
  [Result](docs/evidence/nearby-20261024/relay-final16-stream-renewed.json).
- Renewed worker request `REDACTED-ID-7ce234021035`: HTTP accepted,
  same-ID replay deduplicated, real Bedrock returned water packs/2 ready for review
  in2.697s; `allocation_authorized=false`. No stock was changed by this check.
  [Result](docs/evidence/nearby-20261024/relay-final16-cloud-renewed.json).
- App caps100 request/preview allocations and20 transcription allocations;
  four simultaneous live sessions, one per account. Final observed counters24/8,
  leaving76/12. Two earlier direct AWS probes ran outside application counters.
  Account service quotas are documented separately in
  [hosting](cloud/docs/DEMO_HOSTING.md); they are not performance guarantees.

### Hardware, physical acceptance and remaining claims

Host: Apple M3 Pro,18GiB, macOS26.6.2(25G83); Xcode26.1.1(17B100), Swift6.2.1,
iOS/macOS26.1 SDKs. Simulator: iPhone17Pro and17ProMax, iOS26.1. Cached paired
physical records: iPhone15ProMax/iOS27.0.1(24A446), iPhone16/iOS26.2(23C55),
Developer Mode enabled. Phones were disconnected during final builds; prior
installation/launch evidence below remains historical. Release signing used
teamU4G9LV39GM; the original development bundle uses team3TUBL56UTY.

| Required physical claim/test | Current result |
|---|---|
| A: direct offline P2P communication | **NOT TESTED** under controlled physical isolation |
| B: three-device store-carry-forward | **NOT TESTED physically**; separate native simulator/Mac encounters PASS |
| C: bidirectional receipt delivery | **NOT TESTED physically**; two-hop signed receipt software test PASS |
| Infrastructure-independent wireless path | **NOT VERIFIED**; no controlled phone radio/no-router evidence |
| D/E: duplicates and repeated unexpected failures | **NOT TESTED physically**;62 unit tests and3/3 TCP failure trials PASS |

Physical discovery time, range, latency and failure rates were not measured. Run
[TEST_PLAN.md](TEST_PLAN.md) A–E and [MORNING_DEMO.md](MORNING_DEMO.md) before
claiming phone success. Further resilience work includes long carries, reboot/power
loss, clock drift, congestion/ten peers, key rotation/revocation, noisy speech,
battery/background behavior and security review. Nearby staff replies/inventory
history and Android transport are not implemented. Foreground encounters and online
pre-enrollment are required. This remains a synthetic-data engineering prototype.

## Build 15 — frontend redesign, 2026-10-24

The user rejected build14's decorative banner/card/icon treatment. Build15 replaces
it with flat warm-neutral/charcoal surfaces, serif page headings, restrained rust
accents, text tabs, plain supply choices, a message-first composer and rule-separated
inbox/inventory rows. The app icon is an R with a small rust rule. Core networking,
cloud contracts, persistent identities and stock rules are unchanged. DESIGN.md
records the requested direction for future edits.

- **PASS:** Mac, signed iOS Simulator, signed physical iOS and release archive;
  TestFlight upload succeeded02:45:16PDT. [Build markers](evidence/build15/build-markers.txt).
  Browser sign-in remains expired, so internal availability/new release notes are
  unverified; upload does not mean external beta approval.
- **PASS:**49Swift tests, [log](evidence/build15/swift-tests.txt). No backend code
  changed; its prior67-test result is unchanged, not a new test run.
- **PASS, visual UI:** iPhone17ProSimulator/iOS26.1 light composer, corrected local
  text entry, software keyboard/Done, visibleReviewrequest, review sheet and voice
  view. Native Mac dark appearance: coordinator inbox and inventory. These checks
  used existing authenticated records; no new request/AI/audio/stock action was sent.
- **PASS, install/preservation:** both original phone apps reportbuild15. iPhone16
  launched and retained33/33messages; 15ProMax retained33/33messages, but iOS blocked
  launch because it was locked. The operator was asked to unlock/open it. Read-only
  post-install exports verified both device identities, shelters, receipt states and
  each device's20immutablecloudsubmissions. [15ProMax](evidence/build15/iphone15promax-install.json),
  [16](evidence/build15/iphone16-install.json). Phone Keychain accounts were not replaced.
- **NOT TESTED:** physical visual acceptance, largest Dynamic Type/older devices,
  real phone microphone/GPS and controlled physical no-router tests in this pass.
  This does not close the separate cloud/P2P routing gap or establish ASR latency.

## Build 14 — interface polish, 2026-10-24

The update changes presentation and client-side filtering only. Shared headers,
navy/teal colors, supply icons, labeled fields, a fixed Review and send action,
request status badges, Open/All/Closed filters, inventory emphasis and numbered
voice steps replace the plain forms. The third tab is now Nearby, distinguishing
device chat from request-specific shelter conversations. Core protocol, durable
IDs, cloud operations and inventory transaction rules are unchanged.

- **PASS:** Mac, signed iOS Simulator, signed physical iOS and Release archive builds;
  [build markers](evidence/build14/build-markers.txt). **49 Swift tests pass**, [log](evidence/build14/swift-tests.txt).
  The unchanged backend retains the prior 67-test result; it was not rerun for presentation-only changes.
- **PASS:** native Mac dark appearance shows inbox/Closed filter and inventory cards.
  iPhone 17 Pro simulator/iOS26.1 light appearance verified Help, selected supply,
  quantity/people focus, software keyboard, Done dismissal, fixed review action,
  review sheet/Edit and voice screen. No new AI/audio/stock operations were used.
  [Recorded checks](evidence/build14/ui-verification.json). Simulator checks are not physical phone evidence.
- **PASS:** original phone installs and launches. The 15 Pro Max retained32/32messages;
  iPhone16 retained33/33. Each retained20prior immutable cloud submissions, identity,
  shelters and final receipts; [A](evidence/build14/iphone15promax-install.json),
  [B](evidence/build14/iphone16-install.json). Existing Keychain accounts were kept;
  the installer did not inject or replace phone sessions in this update.
- **PASS:** TestFlight14 upload at02:19:07PDT. Release contains no debug enrollment
  credentials; external beta review remains a separate gate.
- App Store Connect browser sign-in expired before internal build14 availability could be checked; upload success does not establish tester availability.
- **NOT TESTED:** largest accessibility text, older OS/device sizes, physical phone
  visual acceptance, microphone/GPS or no-router wireless acceptance in this pass.
  No new claim of automatic cloud-to-P2P failover or ASR speed is made.

## Current release — 0.1.0 (13), 2026-10-24

**Implemented and ready for the operator's two-phone cloud test.** Public Help / Requests / Messages and coordinator Inbox / Inventory / Messages now use server-authorized roles. The workflow covers voice upload/transcription, editable AI preview before Send, optional one-shot location or landmark, durable drafts/outbox, coordinator reservation/handover/release, inventory and request history. See [MOBILE_TEST.md](MOBILE_TEST.md).

| Verification | Actual result |
|---|---|
| Shared Swift tests | **PASS: 49, 0 failures**, [log](evidence/build13/swift-tests.txt) |
| Backend tests | **PASS: 67**, including transaction races, durable retries, preview reuse, inventory and bounded batch reads, [log](evidence/build13/backend-tests.txt) |
| Separate-process TCP control | **PASS**, including interrupted frame and relay process restart; loopback only, [log](evidence/build13/tcp-control.txt) |
| Build 13 native Mac / signed iOS / release archive | **PASS**, [markers](evidence/build13/build-markers.txt) |
| Physical 15 Pro Max / iPhone 16 install and launch | **PASS**; each retained all 32 prior messages, identity, shelters and final-receipt state. [15 Pro Max](evidence/build13/iphone15promax-install.json), [16](evidence/build13/iphone16-install.json) |
| Native Mac password + MFA, Bedrock preview, Review/Send | **PASS** against public HTTPS and actual AWS; request `REDACTED-ID-4732500990f0`, [independent readback](evidence/build13/native-mac-ui-request-readback.json) |
| Native Mac coordinator approve / inventory / release | **PASS**: 20 on hand → 2 reserved / 18 available → release restores 20 available; [independent ledger readback](evidence/build13/native-mac-ui-release-readback.json) |
| Swift live HTTP preview/location/fulfillment/retry | **PASS** with synthetic location 0,0; request `REDACTED-ID-d4dddd0f1bf6`. Reserve/fulfill replays did not duplicate stock movement; synthetic consumption restored. [Live evidence](evidence/build13/swift-live-flow.json) |
| Fixture audio→preview→location→send→inventory | **PASS**, simulated providers; [separate fixture evidence](evidence/build13/swift-fixture-flow.json) |
| Build 13 TestFlight | Upload **PASS** at 01:47 PDT; Apple showed **Testing** in internal RELAY Development group, 1 tester. What to Test saved. External build submission remains blocked behind the already submitted beta review. |
| Phone microphone, real GPS, full phone tap sequence | **NOT TESTED by agent**; operator test now required. Native WAV picker correction compiled, post-fix picker UI not reverified. |
| Controlled physical no-internet/no-router tests A–E | **NOT TESTED**; user reports nearby messaging worked, but no controlled network-state evidence was captured. |

Current physical devices: iPhone 15 Pro Max, iOS **27.0.1 (24A446)**; iPhone 16, iOS **26.2 (23C55)**. Host remains M3 Pro / macOS 26.6.2, Xcode 26.1.1 / iOS and macOS 26.1 SDKs. Original phone bundle `org.relay.prototype.ios` was signed using development team 3TUBL56UTY; release bundle `com.nikilthalapaneni.relay` used enrolled team U4G9LV39GM. No data migration between these separate installations is claimed.

The owned debug phones were prepared as Requester-A (15 Pro Max) and Dispatcher-A (16) using existing MFA-authenticated sessions verified against `/v1/me`. One-use files were consumed and deleted, and both cached authorized shelter directories. The importer is DEBUG-only; the release binary was checked to exclude its filename. Normal native password/MFA sign-in was separately exercised on Mac; long-duration native Keychain refresh and account-switch race handling need further verification.

The current API and worker run on this Mac with actual Cognito, DynamoDB, S3, Transcribe and Bedrock Nova Lite. Internet remained available. Public inbox reads after the bounded batch-read update returned 19 items in **0.449 s and 0.478 s**, versus an earlier single **7.77 s** observation. These are three individual snapshots, not a load benchmark or wireless metric. [Read evidence](evidence/build13/public-inbox-read.json). The API was restarted alone; no parallel old worker or old API remains.

Native preview `REDACTED-ID-cac05d978eba` used real Bedrock, then was reused when sent without a second analysis. Native coordinator reserve operation `REDACTED-ID-af7c3f4dc64f` and release `REDACTED-ID-659811caf3c4` each appear once in the ledger. Final synthetic water stock at 08:52 UTC was on_hand=20, reserved=0, available=20, revision=6. No physical handover was claimed. Counters then showed **19/30 analysis slots and 4/5 audio allocations**; one audio allocation remained. New tests may change these values.

Remaining boundaries: the cloud composer waits for its origin device to regain internet; authenticated carrier-to-cloud ingestion and encrypted location/reply relay are pending. The existing P2P engine remains plaintext and foreground-only. The Mac must remain online/awake for cloud hosting; permanent AWS deployment still needs the organizer role. No measured radio range, noisy-ASR quality, physical resilience, background mesh or autonomous dispatch claim is made.

## Historical initial environment and access

The table below records the first session before physical phones and signing were available. It is superseded by the current release results above.


| Item | Observed result |
|---|---|
| Development hardware / available physical C | Apple M3 Pro, model Mac15,6, arm64 |
| Host OS | macOS 26.6.2, build 25G83 |
| Xcode | 26.1.1, build 17B100 |
| Swift | Apple Swift 6.2.1, swiftlang-6.2.1.4.8 |
| SDKs used | iOS 26.1, iOS Simulator 26.1, macOS 26.1 |
| Simulator UI test | iPhone 17 Pro simulator, iOS 26.1; **not a physical iPhone** |
| Physical iPhones A and B | Unavailable to this session: `xcrun devicectl list devices --timeout 10` returned `No devices found.` |
| Development signing identities | `security find-identity -v -p codesigning`: `0 valid identities found` |
| iOS device signing | **BLOCKED**: actual signed-build attempt failed: `Signing for "RELAY-iOS" requires a development team.` No profile/install on a phone was completed. |
| macOS signing | **PASS for local ad hoc signing**; `codesign --verify --deep --strict` reports valid on disk/designated requirement; sandbox client/server entitlements present. This is not Developer ID/notarization or iOS provisioning. |
| Operator network conditions | Physical isolation was **not performed**. Host network/radio settings were left unchanged. No internet-off or no-router certification was made. |

Evidence: [environment](evidence/environment.txt), [devices](evidence/devices.txt), [identities](evidence/signing-identities.txt), [actual iOS signing failure](evidence/signing-ios.txt), [Mac signing verification](evidence/signing-macos.txt).

## Builds and automated verification

| Check | Result | Actual evidence |
|---|---|---|
| Shared Swift package + RelayLab | PASS | [build-core.txt](evidence/build-core.txt) |
| Native macOS arm64 Debug app | PASS, ad hoc signed and launched | [build-macos.txt](evidence/build-macos.txt), [native events](evidence/native-mac-events.txt) |
| iOS Simulator Debug app | PASS, installed and launched | [build-ios-simulator.txt](evidence/build-ios-simulator.txt), [launch record](evidence/simulator-launch.txt) |
| iOS arm64 device SDK build | PASS **unsigned only** | [build-ios-device-unsigned.txt](evidence/build-ios-device-unsigned.txt) |
| Unit/integration tests | PASS: **17 tests, 0 failures** | [automated-tests.txt](evidence/automated-tests.txt) |
| Real TCP separate-process control | PASS, including actual SIGKILL/restart of B | [tcp-control.txt](evidence/tcp-control.txt) |
| Native Mac ↔ iOS Simulator Bonjour/UI control | PASS for discovery, request, receipt, storage | [Mac log](evidence/native-mac-events.txt), [simulator log](evidence/ios-simulator-events.txt) |
| Existing parent-repo tests | PASS: 30 tests, 1 expected skip | [repo-regression.txt](evidence/repo-regression.txt) |

Initial Mac build issues were corrected: Debug architecture settings were aligned with the package; code signing rejected Finder/file-provider metadata on the generated `.app` under Documents, so final Mac DerivedData was moved to `/tmp/RELAY-mac-build`. No source permissions/security protections were weakened. The iPad orientation plist warning was corrected. Xcode may emit its informational App Intents metadata-extraction warning because this app does not use that framework.

The 17 tests cover JSON roundtrip and field names, framing at every byte split and coalesced frames, malformed/version rejection, SQLite restart identity/message/ACK recovery, duplicate/UUID collision handling, expiry and final-hop boundaries, shorter duplicate routes, inventory filtering, same-link and reconnected lost-ACK retries, A→B→C and receipt return across store reopen, wrong claimed receipt origin, logical route blocking, unsolicited ACKs, durable receipt state after sender restart, and atomic rollback/no ACK when capacity cannot accommodate request plus receipt.

**Repeated-failure measurement is simulated only:** one test deliberately drops a partial frame in **30 consecutive encounters**, asserts no receiver insert/false delivery, then succeeds on attempt 31 with one logical message. Another repeats the same destination message 20 times and verifies only one generated receipt. These are deterministic assertions, not physical failure-rate/range/latency estimates.

## Real TCP control evidence (three processes on one Mac)

Final captured run: **2026-10-23 22:35:31–22:35:32 UTC**. All connections used explicit `127.0.0.1`; logs report `interfaces=[lo0:loopback]`, `wifi=false`, `cellular=false`. Bonjour was disabled for this experiment. Host internet status was irrelevant to loopback and not certified as disabled.

| Node/message | Actual UUID |
|---|---|
| A process | `REDACTED-ID-934bc7d3fae3` |
| B process | `REDACTED-ID-b328e46c7597` |
| C process | `REDACTED-ID-3156918454ea` |
| Original request M001 | `REDACTED-ID-18f6f1d330f2` |
| Destination receipt | `REDACTED-ID-1988fd14a03d` |

The [reproducible harness](scripts/tcp_experiment.py) verified:

1. A's deliberate half-frame send was discarded. B had no M row; A had neither an ACK nor final receipt.
2. A reconnected to B; B persisted M at hop 1. Duplicate transmission left one row at B.
3. A stopped networking. **B was killed with SIGKILL** after its committed ACK, then relaunched against the same SQLite WAL store. Identity and M survived.
4. B connected separately to C, which persisted the original at hop 2 and generated a separate receipt. B persisted the receipt. Repeating M to C left one request and one receipt.
5. C stopped networking. B's process was terminated/restarted again, then connected to A. A persisted the receipt at hop 2 and recognized it as final destination delivery.

Selected actual output (full timestamps, session IDs, paths, attempts, and final snapshots are in the raw log):

```text
2026-10-23T22:35:31.778345+00:00 PASS control interruption: no destination insert or false ACK
2026-10-23T22:35:31.991722+00:00 B deliberate SIGKILL after durable acceptance
2026-10-23T22:35:32.028058+00:00 PASS actual B SIGKILL/restart: same device ID and message recovered from SQLite WAL
2026-10-23T22:35:32.246664+00:00 PASS separate B->C encounter; one request, one receipt; A disconnected
2026-10-23T22:35:32Z [REDACTED-ID-934bc7d3fae3] FINAL_RECEIPT_RECOGNIZED id=REDACTED-ID-1988fd14a03d original=REDACTED-ID-18f6f1d330f2
2026-10-23T22:35:32.500063+00:00 PASS C->B->A receipt across second actual B process restart
```

The host processes are not three physical devices. This proves application/protocol/persistence behavior over the actual TCP adapter, not local-radio compatibility or infrastructure independence. These short control timings are not a performance benchmark.

## Native UI and Bonjour control evidence

Native Mac device UUID: `REDACTED-ID-337a93bc8deb`. iOS Simulator UUID: `REDACTED-ID-9db6fe6380c4`.

- The Mac UI saved request `REDACTED-ID-bce9eb27c954` at 22:28:40 UTC. After stopping networking, quitting, and relaunching at 22:28:53 UTC, the same UUID/message was visibly retained. It was still queued with no final receipt.
- Both apps started Bonjour. Mac discovery at 22:29:31 UTC listed the simulator, and the connection became ready at 22:29:32 UTC. Timestamps have second-level precision; no controlled discovery-latency measurement was made.
- Discovery included `awdl0`, **but the actual connection log showed `interfaces=[en0:wifi,lo0:loopback]` with both endpoints on `10.251.234.66`** (same host). This is expressly not evidence of an AWDL wireless data path or two physical radios.
- The Mac UI sent synthetic request `REDACTED-ID-27fe08e83198` to the simulator. At 22:29:43 UTC the Mac logged a destination storage ACK with **one observed 9 ms ACK interval**, followed by recognition of separate receipt `REDACTED-ID-1fd2e3f54b5b`. This is one same-host control observation, not a wireless latency estimate.
- Both apps showed the distinct receipt state. Networking was then stopped on both apps. After installing/relaunching the latest simulator build, the simulator still displayed the original message and receipt; its role selector was exercised successfully. The [actual simulator screenshot](PUBLICATION_CLEANUP.md) shows stored synthetic data and receipt status. It is labeled simulator evidence only.
- No physical-device Local Network prompt was tested. Mac/simulator listener/browser reached ready with available local access; the session did not require an interactive permission approval. This does not establish physical iOS permission behavior.

Read-only storage exports: [native Mac messages](evidence/native-mac-stored-messages.json), [simulator messages](evidence/ios-simulator-stored-messages.json). Raw logs and synthetic snapshots are retained; no private keys, passwords, or provisioning profiles are included. The source/config hashes in [source-sha256.txt](evidence/source-sha256.txt) identify the delivered implementation.

## Mandatory physical acceptance results

| Test | Physical result | Network state / reason |
|---|---|---|
| A — direct offline iPhone A→B | **NOT TESTED** | Both phones are now installed/launched; no physical no-internet/no-AP delivery result or logs have been captured. |
| B — A→B→C, B restart | **NOT TESTED** | Protocol behavior passes in simulated/TCP controls; no three-device radio encounters. |
| B variant — A/C genuinely out of range | **NOT TESTED** | No physical separation or range experiment. Logical route enforcement is implemented/tested only. |
| C — physical C→B→A receipt | **NOT TESTED** | Return receipt passes in software controls only. |
| D — duplicate physical delivery | **NOT TESTED** | Duplicate suppression passes simulated/TCP controls; no physical repeated transmissions. |
| E — unexpected physical disconnection | **NOT TESTED** | Partial TCP frame and process failure controls pass; no range/radio disruption trials. |

No physical message IDs, radio discovery times, transfer latency distribution, packet captures, or success rate exist for A–E. The UUIDs above belong to software controls and must not be repurposed as hardware evidence.

## Separate claim verdicts and next gates

| Claim | Verdict |
|---|---|
| 1. Direct offline P2P communication verified | **NO — physical verification blocked** |
| 2. Three-device store-and-forward verified | **NO on physical devices**; software engine plus three separate TCP processes verified |
| 3. Bidirectional delivery verified | **NO on physical devices**; request and return receipt verified in controls |
| 4. Infrastructure-independent wireless path verified | **NO**; peer-to-peer opt-in is configured, path independence remains unverified |
| 5. Reliability under repeated failures measured | **SIMULATED ONLY**: 30 interrupted encounters then successful retry; physical reliability not measured |

Next: execute [TEST_PLAN.md](TEST_PLAN.md) A→E on the installed physical phones and Mac with exported evidence. No password needs to be sent to this agent. Verify OS permission behavior and actual no-AP conditions, repeat with A/C out of range, then collect physical failure/latency/energy/range statistics. Long carries, device reboot/power loss, quotas, clock drift, background suspension, congestion and adversarial peers remain untested. Plaintext/unauthenticated security, foreground-only behavior and encounter dependence rule out a production disaster-resilience claim.


## Physical-test setup follow-up — 2026-10-23

The user subsequently connected a physical iPhone 15 Pro Max, running iOS 27.0.1 (24A446), over USB. The earlier no-device observation above remains the record of the initial implementation session. Current probe: paired, Developer Mode disabled, developer disk services unavailable. Xcode has a signed-in Personal Team with no provisioned devices; an automatic-signing build failed because no registered device/profile was available. Mac RELAY is prepared as Receiver C with networking stopped. The second iPhone has not yet been observed. Physical A–E and wireless path verification remain NOT TESTED. See [setup probe](evidence/physical-setup-20261023.txt).

An explicit build targeting the connected physical phone subsequently confirmed the immediate blocker: `Developer Mode disabled`. No Xcode/iOS software update has been established as necessary by that attempt. The user reports slow internet; no large update was initiated.


## First physical installation follow-up — 2026-10-23

Developer Mode was enabled on the iPhone 15 Pro Max (iOS 27.0.1), and developer disk services became available. The existing Xcode 26.1.1 / iOS 26.1 SDK successfully built and development-signed RELAY using the signed-in Personal Team. Automatic provisioning and USB installation of `org.relay.prototype.ios` succeeded. No software update was needed for these steps. Local signature verification passed, signing-input entitlements match the provisioning profile, and the connected phone is included. The profile expires **2026-10-30 22:50:54 UTC**.

The first launch was denied with the iOS Security message covering invalid signature, inadequate entitlements, or a developer profile not explicitly trusted by the user. Given the successful local checks, developer-profile trust is the next on-phone step; launch success is not yet claimed. The second phone is not installed yet. **Physical tests A–E and infrastructure independence remain NOT TESTED.** Sanitized evidence: [first-phone installation](evidence/physical-install-first-phone.json).

**Launch retry succeeded:** after the user completed the on-phone trust step, `devicectl` launched RELAY at 2026-10-23 22:54:12 UTC. The physical app container contains SQLite/WAL/SHM and an `APP_OPEN` record, with persistent UUID `REDACTED-ID-85ca2bd297a6` and zero messages. See [physical launch evidence](evidence/physical-first-phone-launch.txt). This confirms installation/launch/storage initialization on one actual iPhone, not wireless delivery. The second phone and physical A–E tests remain pending.


## Second phone setup and distribution assets — 2026-10-23

An iPhone 16 (iPhone17,3) running iOS 26.2 (23C55) is now detected over USB and paired. Its Developer Mode remains disabled; installation is pending the user enabling it. [Second-phone probe](evidence/physical-second-phone-setup.json). Physical A–E tests remain NOT TESTED.

Added opaque app-icon assets for iOS/macOS and deterministic generation. Both [iOS device build](evidence/build-appicon-ios.txt) and [macOS build](evidence/build-appicon-macos.txt) pass with the icon. Core engine and protocol sources were unchanged, so earlier 17-test evidence remains applicable; tests were not rerun solely for icons. Current setup source hashes: [source-sha256-physical-setup.txt](evidence/source-sha256-physical-setup.txt). [TestFlight preparation](TESTFLIGHT.md) includes beta metadata drafts; no distribution upload or review submission has occurred.

**Second-phone installation succeeded:** Developer Mode and DDI services were enabled, and the signed build installed on the physical iPhone 16. The first iPhone was updated with the same build over its existing paired local-network connection. Both devices are included in the provisioning profile (expires 2026-10-31 00:50:21 UTC). This setup network use is not an offline transmission test. Initial launch on the second phone hit the generic iOS signing/trust Security denial; local signature checks passed and user profile trust is pending. [Installation evidence](evidence/physical-second-phone-install.json). Physical A–E remain NOT TESTED.

**Second-phone launch succeeded after trust:** `devicectl` confirmed launch on iPhone 16 at 2026-10-24 00:53:28 UTC. Verified persistent UUID `REDACTED-ID-1684768e4451`, a startup log, and an empty message store. [Launch evidence](evidence/physical-second-phone-launch.txt), [startup events](evidence/physical-second-phone-startup-events.txt), [physical peer map](evidence/physical-peer-map.json). Mac RELAY UI was confirmed stopped. The operator is setting up an unplugged, cellular-off/no-AP phone-to-phone discovery test; connection and delivery outcomes are pending.

## Keyboard fix and TestFlight account setup — 2026-10-23 PDT

Version **0.1.0 (2)** adds explicit focus state and a navigation Done button, interactive scroll dismissal, and focus clearing on destination selection/send. In the iPhone 17 Pro / iOS 26.1 simulator, software keyboards for both destination and multiline message fields disappeared after tapping navigation Done, with text preserved. [Observed UI checks](evidence/keyboard-ui-check.txt), [actual post-dismissal simulator screenshot](PUBLICATION_CLEANUP.md). The keyboard accessory toolbar did not expose its own Done control in this simulator, so the navigation Done button is the verified path.

[Simulator build](evidence/build-keyboard-ios-simulator.txt), [macOS build](evidence/build-keyboard-macos.txt), and [unsigned iOS Release archive](evidence/archive-keyboard-ios-unsigned.txt) all **PASS**. The final archive's plist confirms version 0.1.0, build 2, and `ITSAppUsesNonExemptEncryption=false`; source review found no application encryption or third-party crypto. These are local compile/UI results, not App Store validation or physical keyboard verification. Shared engine sources were unchanged; the earlier 17-test results remain applicable and were not rerun solely for this UI/metadata change. [Current source/config hashes](evidence/source-sha256-keyboard-testflight.txt).

User completed App Store Connect sign-in for the enrolled developer account. Verified paid team **U4G9LV39GM**; App Store Connect lists no apps. New App opens an **Agreement Update** blocker. Apple Developer account states the updated Program License Agreement must be accepted to regain membership resources. User was asked to review/accept directly in Apple's page. No agreement accepted by agent, app record created, distribution signing completed, build uploaded, beta review submitted, or TestFlight link created. Physical phones still contain the earlier development build. Publication continuation and repeatable upload script: [TESTFLIGHT.md](TESTFLIGHT.md).

## TestFlight upload and review submission — 2026-10-23 PDT

The user accepted Apple's updated agreement. Registered `com.nikilthalapaneni.relay` under enrolled team U4G9LV39GM after Apple rejected the original Personal Team identifier as unavailable. Created **RELAY Offline Lab**, App Store Connect ID **6826458231**. Registered the previously verified Sender A device for the new team's initial development profile; this resolved the first archive attempt's no-registered-devices error without reconnecting a phone.

Signed release archive **PASS**, local signature verification **PASS**, App Store Connect export/upload **PASS** at **18:18:46 PDT**. Apple processed version **0.1.0 (2)** and exposed it as Ready to Submit. Created internal group RELAY Development and external group RELAY Teammates; submitted the latter's build with test instructions and user-approved review contacts. Verified the build row now reads **Waiting for Review**. No Apple review approval or TestFlight phone installation is claimed.

Public invitation created: **https://testflight.apple.com/join/paGggTvE**, open to anyone with the link, limit 100. Apple's group page explicitly states: `Testers cannot join public link until this group has an approved build.` Automatic tester notification is selected for the submitted build. No individual teammate invitations or App Store Connect account access were granted.

Evidence: [signed archive log](evidence/archive-testflight-build-2.txt), [actual upload output](evidence/testflight-upload-build-2.txt), [sanitized build/review/link record](evidence/testflight-upload-build-2.json), [source/config hashes](evidence/source-sha256-testflight-build-2.txt). The generated iOS project now defaults to the enrolled team/identifier; the archive used those same effective settings via command-line overrides. Private contact details, credentials, provisioning profiles and signing keys are not included in this release record. No core protocol code changed or additional wireless acceptance evidence was collected. Physical claims 1–4 remain unverified; repeated-failure measurements remain software-only.


### Immediate internal-testing availability

After the user reported a tight deadline, added the existing account holder to RELAY Development without adding account roles. Verified App Store Connect **1 Tester**, **Invited**, and internal build **0.1.0 (2): Ready to Test**. The external submission remains pending; its public invitation gate is separate. User still needs to accept the internal invitation/install through TestFlight. No inbox delivery, physical installation of build 2, or offline transfer is claimed. Device probe at this point sees iPhone 15 Pro Max available/paired and iPhone 16 unavailable.


## Usability refresh / build 3 — 2026-10-23 PDT

User requested a usable, attractive app for immediate testing on two phones. Replaced the engineering form with Messages, Nearby, and Tools; navy connection cards and adaptive light/dark accents; a validated compose sheet with known-peer/manual destinations, synthetic templates and reliable Done controls; message filters and detail progress; Reply for incoming requests; copy/share identity; and retained path/log/duplicate/interruption diagnostics. New stores default to unrestricted nearby connections; existing saved role/forced-route settings are preserved. Changing setup reconnects only if networking was already active. Saves dismiss the composer only after durable success; unsaved drafts are memory-only. No wire protocol/database schema change, cloud, AI, or new transport was introduced.

| Build 3 check | Actual result |
|---|---|
| iOS simulator / iOS development-signed / macOS builds | **PASS**; final source compiled for all three |
| Paid-team release archive and App Store Connect upload | **PASS**; uploaded 18:52:36 PDT; processed; internal group shows **Testing** |
| XCTest unit/integration suite | **17 tests, 0 failures** |
| Three-process actual TCP / SIGKILL / duplicate / retry / return receipt control | **PASS**; loopback only |
| Simulator invalid destination validation | **PASS**; invalid UUID disables Save & send and shows guidance |
| Keyboard dismissal | **PASS in simulator**; in-message Done removed software keyboard and retained text; navigation Done also present |
| Queued UI request after app terminate/relaunch | **PASS**; same synthetic request retained and still queued before connection |
| New UI request, reply and both final receipts | **PASS Mac↔iOS Simulator control**, not a physical wireless test |
| Mac UI navigation / retained old messages / light and dark presentation | **PASS** for observed controls and visual inspection |
| iPhone 15 Pro Max direct update / launch | **PASS**; 0.1.0 (3), same UUID `REDACTED-ID-85ca2bd297a6`; empty store before and after, no data reset |
| iPhone 16 build 3 update | **PASS** after it became reachable; installed and launched at 18:58:01 PDT; UUID/store preserved |
| Physical no-internet/no-router delivery | **NOT TESTED**; no physical radio/path claim |

The new same-host UI request ID is `REDACTED-ID-4243100fd0a1`, simulator origin `REDACTED-ID-ee5abc667601`, Mac destination `REDACTED-ID-337a93bc8deb`, final receipt `REDACTED-ID-436549feb3b8`. The simulator first saved it with networking paused; process terminate/relaunch retained it. After discovery, Mac persisted it and returned a separate receipt. The Mac Reply action prefilled the simulator address and sent a synthetic reply, which also obtained a final receipt. Both stores were checked. Mac and simulator networking were paused afterward for the physical phone test. Final presentation refinements changed sorting/colors only; final builds and visual checks passed afterward.

Evidence: [17 tests](evidence/automated-tests-build-3.txt), [TCP control](evidence/tcp-control-build-3.txt), [UI request/reply record](evidence/ui-build3-control.json), [Mac events](evidence/ui-build3-mac-events.txt), [simulator events](evidence/ui-build3-simulator-events.txt), [actual final simulator screenshot](PUBLICATION_CLEANUP.md), [queued screenshot](PUBLICATION_CLEANUP.md), [physical install record](evidence/physical-build3-install.json), [physical launch](evidence/physical-build3-a-launch.txt), [release record](evidence/testflight-upload-build-3.json), [upload output](evidence/testflight-upload-build-3.txt), [source hashes](evidence/source-sha256-ui-build3.txt).

Both physical installations are now complete. Required next physical steps: execute Test A with both phones unplugged and documented radio isolation. In Tools, turn off Force A → B → C on both for the direct test; start connections; choose the other phone in Nearby; send synthetic data and capture the actual request/receipt logs. Follow B–E afterward; the five final claim verdicts remain unchanged until those physical results exist.


**Second phone update completed:** iPhone 16 became reachable after the earlier unavailable probes. Backed up its existing store, installed and launched version 0.1.0 (3), and confirmed UUID `REDACTED-ID-1684768e4451` and all pre-existing message IDs survived. The store was empty before and after this update. Both phones now run the redesigned build under their original identifiers. [Second-phone install](evidence/physical-build3-b-install.txt), [launch](evidence/physical-build3-b-launch.txt), [combined verification](evidence/physical-build3-install.json). This is installation evidence, not offline wireless success.


## Build 4 — chat UI and repeat-send fix, 2026-10-23 PDT

User reported no accessible new-message action after sending and requested a normal chat UI with appropriate sizing. Build 4 replaces the modal send-and-dismiss flow with peer conversations and a fixed bottom composer. Saving clears text only after success and retains the current conversation/focus; the input is not disabled during the asynchronous save, and newly typed text is preserved if it differs from the submitted snapshot. The chat list has an unconditional, labeled New chat control. Bubbles use body-sized text, width limits, timestamps, and separate queued / relay-saved / destination-saved / final-receipt states. New chat can open known or manually addressed peers. Relay traffic and receipt envelopes remain in Tools → Open durable queue.

Added `Conversations.swift`, a presentation-only projection, and four regression tests covering incoming/outgoing grouping, carried-traffic exclusion, receipt-envelope suppression with retained delivery state, and separate-peer/latest-chat ordering. Wire protocol, networking and durable schema are unchanged. **21 tests pass** (17 existing plus 4 new). Final iOS Simulator, signed iOS, macOS and paid-team release archive builds pass.

Observed simulator UI regression: sent `SYNTHETIC CHAT-004: First consecutive message.` with the software keyboard visible; the conversation, keyboard and empty composer remained. Typed and sent `SYNTHETIC CHAT-004: Second message, same chat.` without reopening a composer. Done dismissed editing. Both messages survived process terminate/relaunch. New chat remained available and selected the existing peer's thread; no duplicate thread/bubble was created. macOS chat/back navigation also returned to the persistent New chat control. These are software UI tests, not physical radio tests. [Repeat-send record](evidence/ui-build4-repeat-send.json), [actual simulator chat screenshot](PUBLICATION_CLEANUP.md), [21-test output](evidence/automated-tests-build-4.txt).

Physical deployment: both iPhones successfully installed and launched build 4 at **19:19:13 PDT** under the original bundle ID. A kept its UUID and **9 stored items**; B kept its UUID and **10 stored items**. All pre-update message IDs and immutable contents were compared and preserved; counts include receipt envelopes. [Verification](evidence/physical-build4-install.json), [A launch](evidence/physical-build4-a-launch.txt), [B launch](evidence/physical-build4-b-launch.txt).

The pre-update phone stores contained actual requests and receipts from the user's encounters. Logs report Wi-Fi paths, including `awdl0:wifi` on A and `en0:wifi` on B, with cellular false on those observed paths. Some sessions involved Mac C, and some were route-blocked or incomplete. Neither radio/router isolation nor separate A–B/B–C/B–A timing was established by this observation. **Do not promote this into an offline physical A–E PASS or an infrastructure-independent path verdict.** Payloads were omitted from the recorded physical summaries. [Observation summary](evidence/physical-prebuild4-observations.json), [A paths/events](evidence/physical-prebuild4-a-transport.txt), [B paths/events](evidence/physical-prebuild4-b-transport.txt).

Paid-team build 4 uploaded successfully at **19:18:26 PDT**, completed processing, and is **Testing** in RELAY Development. Test notes saved. The earlier external build 2 submission was not canceled or replaced. [Release record](evidence/testflight-upload-build-4.json), [upload output](evidence/testflight-upload-build-4.txt), [source hashes](evidence/source-sha256-chat-build4.txt). Mac and simulator left paused after UI verification. Next physical step remains a documented no-router test with the updated phones.


## Build 5 — names, addressing, and forwarding-copy presentation (2026-10-23 PDT)

Read both physical stores without recording their payload text. The iPhone 15 Pro Max held 15 envelopes and the iPhone 16 held 16. Two encountered peers used the same old “Relay B” label. Request `REDACTED-ID-bda7df911b78` originated on iPhone 16 and was explicitly addressed to Mac UUID `REDACTED-ID-337a93bc8deb`; iPhone 15 Pro Max held a forwarding copy, and the origin held final receipt `REDACTED-ID-dac1b1ee6f9a`. This supports the copy/addressing explanation, not an infrastructure-independent acceptance claim. Existing Chats projection already excluded carried messages; the durable queue exposed payload previews and roles made peers ambiguous. [Sanitized addressing evidence](evidence/physical-prebuild5-addressing.json).

Build 5 adds persistent editable device names, optional backwards-compatible hello `display_name`, peer-name storage migration, and name-based presentation with stable UUID routing. Test roles move to Advanced relay test. Tools explains copies, personal vs forwarded traffic, and normal messaging. The queue now explicitly labels forwarding copies and hides their payload text in both collapsed and expanded views. Names do not authenticate identity; storage/transport are still plaintext. Existing route-test settings are preserved and can be disabled with Use normal messaging.

| Check | Actual result |
|---|---|
| XCTest unit/integration tests | **25 tests, 0 failures**, including legacy hello, bounds/control rejection, legacy schema migration/restart, duplicate names/rename, and three-node personal-chat isolation |
| Separate-process Network.framework TCP control | **PASS**, including partial frame, duplicate suppression, actual relay SIGKILL/restart, separate encounters and return receipt; loopback only |
| iOS Simulator, signed iOS, macOS, paid-team release archive | **PASS**, Xcode 26.1.1 (17B100), macOS 26.6.2 (25G83) |
| Mac rename and restart | **PASS**; UI-saved name retained, UUID unchanged |
| Mac ↔ iOS Simulator name exchange | **PASS**; active rename to RELAY MacBook updated the existing simulator conversation after reconnect; simulator name learned on Mac |
| Queue payload-preview separation | **PASS** in Mac UI; expanded forwarding row shows metadata without payload |
| iPhone 16 / iOS 26.2 | **PASS** install/launch build 5; same UUID, all 16 old envelopes and final receipts preserved, schema migrated to 2, default name iPhone 4E32 |
| iPhone 15 Pro Max / iOS 27.0.1 | **PASS** install build 5 and preservation of all 15 envelopes/UUID/receipts; **launch blocked by device lock**. User asked to unlock/open. Name/schema migration occurs on first launch |
| Paid-team App Store Connect upload | **PASS**, 19:37:57 PDT; processed, internal group **Testing**, test notes saved; external build 2 still Waiting for Review |
| Physical wireless A–E | **NOT TESTED** this session; no controlled radio/router isolation or range-separated encounter evidence |

Mac and simulator are paused after the control. Neither the unit tests, loopback control, nor same-host name exchange verifies an offline wireless path. Final claims remain separate: direct offline P2P **unverified**; physical three-device store/carry/forward **unverified**; physical bidirectional receipt route **unverified**; infrastructure-independent path **unverified**; repeated failures **measured in software controls only**, not physical radios.

Evidence: [25 tests](evidence/automated-tests-build-5.txt), [TCP control](evidence/tcp-control-build-5.txt), [UI checks](evidence/ui-build5-names.json), [actual simulator screenshot](PUBLICATION_CLEANUP.md), [physical deployment/preservation](evidence/physical-build5-install.json), [iOS build](evidence/build-names-ios-signed.txt), [Mac build](evidence/build-names-macos.txt), [archive](evidence/archive-testflight-build-5.txt), [upload output](evidence/testflight-upload-build-5.txt).


## Private repository packaging — 2026-10-23 PDT

Initialized a standalone Git repository rooted at RELAY, separate from the parent
Dreamer/HPC repository. Added project-specific agent notes, credential/runtime/build
ignore rules, and the explicitly unimplemented shelter/cloud product scope in README.
Source, Xcode project, app assets, tests, scripts, documentation and existing synthetic
test evidence are included. Build outputs, SQLite stores, signing keys/profiles and
credentials are excluded; a staged-path check and secret-pattern scan found no such
files or matching secret values. This scan is a packaging check, not a security audit.

Exported only staged files into a clean temporary directory and ran `swift test` there:
**25 tests passed, 0 failures** at 21:05:35 PDT. This verifies the shared Swift package
can build/test from the repository contents without the original working tree's
ignored files. [Actual clean-export output](evidence/repository-export-tests.txt).
No application/protocol code changed, no new app build was deployed, and no physical
wireless or cloud behavior was verified during repository preparation.

## Build 6 — first shelter request workflow, 2026-10-23 PDT

Implemented a local shelter directory with separate shelter/receiving-device IDs,
copy/share/import codes, structured requests, a draft saved during editing, review
before submit, atomic draft-to-message submission, My requests and a separate Device
inbox. Public navigation is Help / Requests / Shelters / Messages. Tools is under
Help's gear and discovery under Help → Nearby devices. Existing chat and relay data
remain; structured requests are excluded from personal chat and carried requests do
not appear in a relay's request inbox.

These are synthetic local setup/views, not authenticated staff roles. No backend,
Bedrock, ASR, inventory reservation, assignment, or fulfillment action is implemented.
The final-destination receipt still means durable receipt at a device only. Shelter
entries are unverified; storage/transport remain plaintext. Encoded sharing codes
prevent keyboard smart-quote corruption but provide no confidentiality.

| Check | Actual result |
|---|---|
| Core unit/integration suite | **32 tests, 0 failures** (25 existing + 7 shelter cases) |
| New tests | Directory/code round trip and redirect collision; durable draft/restart; atomic idempotent submit; failed-save rollback; legacy schema/data preservation; old-codec payload preservation/destination binding; structured A→B→C→B→A simulated encounters with interruption, B restart, duplicates, receipt and inbox isolation |
| Three-process Network.framework TCP control | **PASS**; actual partial frame, process kill/restart, duplicates and return receipt on loopback. Software control only |
| iOS Simulator, macOS and unsigned iOS device SDK builds | **PASS**, Xcode 26.1.1 (17B100), iOS/macOS 26.1 SDKs, Mac host macOS 26.6.2 (25G83) |
| Mac shelter creation and simulator code import | **PASS** through actual UI; same shelter and receiving-device IDs |
| Help draft restart recovery | **PASS**; simulator process terminated/relaunched before submit, same draft ID, destination, quantity/unit, details and location retained |
| Review and submission | **PASS** after fixing a first-sheet stale state issue. Review shows selected shelter, 20 Packs and People Unknown. Save opens the locally queued request; Help provides a fresh form |
| Mac→simulator control infrastructure | Both endpoints run on this Mac. Normal network configuration unchanged; no isolation attempted. This cannot establish a physical wireless path |
| Simulator request → Mac inbox → simulator return receipt | **PASS** through Bonjour/Network.framework; Mac inbox displayed one request; sender displayed separate final receipt |
| Existing Mac store preservation | **PASS**; all 18 pre-update envelopes, immutable bodies, receipt fields and device UUID compared against a pre-update SQLite snapshot and preserved |
| Physical iPhone build 6 installs/signing, A–E tests | **NOT TESTED** this session; existing physical devices were not updated |
| Build 6 TestFlight upload | **NOT PERFORMED**; earlier distribution status does not imply build 6 availability |

Actual UI-control shelter ID: `REDACTED-ID-13bbcb690629`.
Request: `REDACTED-ID-835c3efc515e`; simulator origin:
`REDACTED-ID-ee5abc667601`; Mac destination:
`REDACTED-ID-337a93bc8deb`; return receipt:
`REDACTED-ID-6bf9121671b7`. Both apps were paused after the control.

Evidence: [32 tests](evidence/automated-tests-build-6.txt),
[TCP control](evidence/tcp-control-build-6.txt),
[UI control record](evidence/ui-build6-shelters.json),
[sender events](evidence/ui-build6-simulator-events.txt),
[receiver events](evidence/ui-build6-mac-events.txt),
[actual simulator receipt screen](PUBLICATION_CLEANUP.md),
[simulator build](evidence/build-shelters-ios-simulator.txt),
[Mac build](evidence/build-shelters-macos.txt),
[unsigned device build](evidence/build-shelters-ios-unsigned.txt).

Separate physical verdicts remain unchanged: direct offline transfer **unverified**;
physical three-device carry/forward **unverified**; physical return receipt route
**unverified**; router-independent path **unverified**; repeated-failure behavior
**tested in software controls only**. Execute the new shelter extension in TEST_PLAN.md
on physical devices before promoting any of these claims.

### Build 6 TestFlight release follow-up — 2026-10-23 PDT

User explicitly requested shipping build 6. Signed release archive **PASS**, strict
local signature verification **PASS**, App Store Connect upload **PASS** at
**22:36:23 PDT**. Verified archived version 0.1.0 (6), bundle
`com.nikilthalapaneni.relay`, team U4G9LV39GM, iOS minimum 17.0 and unchanged
encryption declaration. Source commit: `180fb8815ea0fe26c9646d2dbecf2430c80ec451`.

Apple processing completed. App Store Connect **RELAY Development → Builds** shows
**0.1.0 (6): Testing**. Saved the build-specific What to Test notes and observed the
Saved state. Apple build ID: `REDACTED-ID-872561becd6d`.
The existing internal group has one tester, still **Invited**; acceptance/download
on a phone is not verified. No new account privileges or individual invitations
were issued. No physical installation or wireless test was performed in this release.

External build 2 remains **Waiting for Review**. Apple displays that only one build
of version 0.1.0 can be submitted to Beta App Review until the existing build is
approved. The existing submission was not canceled or replaced; build 6 is available
to internal testers, not yet through the external public invitation.

Evidence: [release record](evidence/testflight-upload-build-6.json),
[signed archive](evidence/archive-testflight-build-6.txt),
[successful upload](evidence/testflight-upload-build-6.txt),
[source hashes](evidence/source-sha256-testflight-build-6.txt),
[saved tester notes](evidence/testflight-test-notes-build-6.txt).

### Build 6 physical installation — 2026-10-23 PDT

Updated the original `org.relay.prototype.ios` installations using their existing
Personal Team signing identity, preserving the app containers. The first phone
(iPhone 15 Pro Max, iOS 27.0.1 / 24A446) was connected by USB; the iPhone 16
(iOS 26.2 / 23C55) was also reachable through existing pairing. The first phone
already had a separate `com.nikilthalapaneni.relay` build 6 installed; that copy was
not replaced or deleted. Use the original copies launched by this update consistently
when testing so their existing device UUIDs remain the intended addresses.

Signed device build and strict code-signature verification **PASS**. Install and
launch **PASS on both phones**. Before upgrading, stopped the original app processes
and copied their SQLite directories outside the repository. After launching, copied
the updated stores and verified SQLite integrity, schema 3, stable identities, all
old message IDs/immutable contents and all prior final-receipt fields. First phone:
**19 → 19** envelopes, UUID `REDACTED-ID-85ca2bd297a6`. Second phone:
**16 → 16**, UUID `REDACTED-ID-1684768e4451`.

This was installation/data-preservation verification, not a physical delivery test.
Cellular/router/radio isolation was not configured or measured. A–E remain
**NOT TESTED** under the required conditions. No user payloads or databases were
added to evidence. [Installation record](evidence/physical-build6-install.json),
[signed device build](evidence/build-shelters-ios-signed.txt),
[first-phone launch](evidence/physical-build6-a-launch.txt),
[second-phone launch](evidence/physical-build6-b-launch.txt).


## 2026-10-23 23:15 PDT — Build 7 shelter removal and import

- Added reversible local directory removal, a Removed shelters restore list, and
  protection against a stale draft autosave reselecting a removed destination.
  Existing request snapshots, queued messages, final receipts and identities remain.
  Schema stays at 3; the existing metadata table holds removal markers.
- Import has a visible button, Paste, validation and receiving-device preview.
  Whitespace-wrapped codes are accepted within the existing size limit. Copy is
  explicitly local to the source clipboard; Connect is not a prerequisite.
- **PASS:** 35 unit/integration tests, including restart/removal/history retention,
  conflict prevention and malformed/wrapped-code cases. **PASS:** separate-process
  TCP loopback interruption/retry, process restart, duplicates and return receipts.
- **PASS:** iOS simulator, native macOS and development-signed iOS builds; paid-team
  archive and strict app/archive signatures. Xcode 26.1.1, SDKs 26.1, M3 Pro.
- **PASS:** native Mac UI Remove confirmation → hidden entry → Removed shelters →
  Restore; Import opens directly → valid preview/self warning → identical import
  without duplicate entry. Screenshot inspected for usable layout. Simulator build,
  launch and home screenshot passed; simulator action automation failed with
  `noWindowsAvailable`, so interactive checks used the shared native Mac UI.
- **PASS:** direct build 7 install and launch on iPhone 15 Pro Max (iOS 27.0.1 /
  24A446) and iPhone 16 (iOS 26.2 / 23C55), original Personal Team bundle. A used
  USB; B used its paired local-network development connection. Consistent stopped
  pre-update backups and post-update copies passed SQLite integrity checks. A
  retained 24/24 envelopes, 3 final-receipt links and its shelter; B retained 23/23
  envelopes, 4 final-receipt links and its shelter. Bodies/receipts are unchanged.
  Raw phone stores/payloads remain outside Git; evidence records counts only.
- A's saved directory did not contain B's shelter at inspection. No physical user
  shelter was removed by the agent. The separate paid-bundle copy on A remained
  build 6; the original bundle was opened on both phones.
- **NOT TESTED:** physical Remove/Import interaction by the operator; new physical
  shelter transfer; isolated A–E; out-of-range carry; repeated-failure statistics.
  Host and phone radios/infrastructure were not isolated during installation.
  No wireless range, discovery latency or infrastructure independence is claimed.

Evidence: [tests](evidence/automated-tests-build-7.txt),
[TCP control](evidence/tcp-control-build-7.txt),
[Mac UI checks](evidence/ui-build7-shelters.json),
[phone preservation](evidence/physical-build7-install.json),
[iOS simulator build](evidence/build-shelter-removal-ios-simulator.txt),
[Mac build](evidence/build-shelter-removal-macos.txt),
[signed phone build](evidence/build-shelter-removal-ios-signed.txt).

Build 7 paid-team archive/upload also passed: Apple accepted it at 23:12:02 PDT.
Follow-up browser verification confirms processing completed and build 7 is
Testing in RELAY Development. Its build-specific notes were saved with Apple’s
Saved confirmation. The one internal tester is shown with build 6 installed;
no TestFlight build-7 phone installation was checked. External build 2 remains
Waiting for Review. [Archive](evidence/archive-testflight-build-7.txt),
[upload log](evidence/testflight-upload-build-7.txt),
[release record](evidence/testflight-upload-build-7.json).


## 2026-10-24 — Build 8 native cloud and request threads

Implemented native PKCE/Keychain code, authenticated profile/directory, local/cloud
shelter mapping, atomic local-message/cloud-intent persistence, scoped retry queue,
cloud result/history UI, dispatcher/requester replies/progress/cancellation, nearby
request threads and short recording → reviewed transcription input. Added backend
profile/history/event routes with ownership, roles, transitions, revision conflict
and command idempotency. No stock allocation or verified fulfillment is claimed.

| Check | Actual outcome |
|---|---|
| Swift automated suite | **PASS: 43 tests**, including legacy draft decode, atomic outbox rollback/restart, account isolation, exact retry content, PKCE state checks, HTTPS validation and reply dedup/chat exclusion |
| Backend automated suite | **PASS: 35 tests**, including profile, unauthorized history, command replay, transitions/cancellation/restart and concurrent revision conflict |
| Three-process TCP control | **PASS**, interruption/retry/restart/duplicate/return receipt; loopback only |
| iOS Simulator / native Mac / signed iOS builds | **PASS**, Xcode 26.1.1 / SDKs 26.1 |
| Swift → fixture HTTP API | **PASS**, text, WAV, explicit state, duplicate requests/events |
| Swift → real AWS through localhost API | **PASS**, Cognito access token, directory, durable request, Bedrock result, S3 WAV/Transcribe and corrected reviewed text |
| Independent DynamoDB readback | **PASS**, both successful requests, proposals and 3-event histories persisted |
| Mac UI | **PASS**, HTTPS rejection with readable error, request reply/progress queued, reusable composer, Done and screenshot layout inspection; 22 prior envelopes preserved, one new synthetic reply |
| Phone installs / launches / preservation | **PASS**, original bundle; A 28→28 messages and 5 final receipt links, B 27→27 and 4 links; identities and shelters retained |
| Native browser PKCE / refresh / microphone / cloud phone UI | **NOT TESTED**, public HTTPS API absent; CLI tokens are not native sign-in evidence |
| Public API deployment | **BLOCKED**, missing organizer execution role/scoped PassRole; no API URL or deployment |
| Physical A–E / router-independent link / range / repeated failures | **NOT TESTED** in this update |

Actual successful AWS IDs: typed `REDACTED-ID-9d0de59831f3`;
transcription `REDACTED-ID-299dd023b84b`; explicitly reviewed request
`REDACTED-ID-49771301a6d3`. Transcribe returned “Sheltering needs 2
water packs.” The separate reviewed submission used “Shelter A needs 2 water
packs.” Both validated model proposals reported water_packs, quantity 2, unit pack;
allocation_authorized remained false. This synthetic sample is not noisy-speech
accuracy evidence.

The first live attempt failed with an expired token after already accepting request
`REDACTED-ID-17dabe7a94c2`; the Swift journal proves it was not a
zero-write failure. Requester and dispatcher tokens were refreshed privately and
subsequent runs passed. Shared durable counters now read **15 requests / 30** and
**2 transcriptions / 5** (three new request records and one audio job this session).
These are usage bounds, not reconciled dollar charges. No secrets were logged.

Phone A is iPhone 15 Pro Max/iOS 27.0.1 (24A446), B iPhone 16/iOS 26.2 (23C55).
Initial A launch timed out and B was explicitly locked; both passed after the
operator unlocked them. No cellular/router/radio isolation was performed. Saved
phone stores remain outside Git; evidence contains preservation counts only.
Mac synthetic queued reply ID: `REDACTED-ID-2a06d64bf7eb`.

The paid-team build-8 archive/upload succeeded at 23:58:54 PDT on Oct 23. Apple
processing/internal availability is recorded separately; external review is not
implied. Carrier→cloud authentication and trustworthy offline cloud-result return
are still pending; the app refuses to submit another device's request as its own.

Evidence: [Swift tests](evidence/automated-tests-build-8.txt),
[backend tests](evidence/backend-tests-build-8.txt), [TCP control](evidence/tcp-control-build-8.txt),
[fixture HTTP](evidence/swift-http-fixture-build-8.json),
[real AWS HTTP](evidence/swift-http-aws-build-8.json),
[reviewed audio](evidence/swift-http-reviewed-aws-build-8.json),
[DynamoDB readback](evidence/aws-readback-build-8.json),
[Mac UI](evidence/ui-build8-request-thread.json),
[phone preservation](evidence/physical-build8-install.json),
[release](evidence/testflight-upload-build-8.json).

Follow-up: Apple processed build 8; RELAY Development explicitly shows **Testing**.
What to Test notes were saved and confirmed. External build 2 remains Waiting for
Review. No public beta approval or TestFlight build-8 phone installation is inferred.

## 2026-10-24 — build 9 and temporary HTTPS hosting

User authorized Cloudflare hosting after alternatives were checked. The temporary
endpoint is `https://resumes-investigated-striking-mba.trycloudflare.com`, forwarding
through cloudflared 2025.11.1/QUIC to the AWS-mode API on Mac loopback port 8788.
The Python API/worker are on the Mac; this is not an AWS Lambda deployment. A private
configuration copy sets the public URL; the original worker/configuration remain
intact. Internet and ordinary infrastructure were available during these checks.

| Check | Actual result |
|---|---|
| Swift automated suite | **PASS: 43 tests** |
| Backend automated suite | **PASS: 35 tests**, one existing test-client deprecation warning |
| Native Mac and signed iOS builds | **PASS**, Xcode 26.1.1 / SDK 26.1 |
| Public HTTPS health and authorized profile/request reads | **PASS**, including a read after the API restarted with its public-URL config |
| Missing/invalid-token rejection | **PASS**, HTTP 401 on `/v1/me` |
| Private credential filename through public tunnel | **PASS**, HTTP 404; helper is a separate loopback-only server |
| Original-bundle phone upgrade and launch | **PASS** on both, build 9; A 28/28 and B 27/27 prior messages preserved, including exact final-receipt links/shelters/identities |
| TestFlight archive/upload | **PASS**, upload accepted at 00:32:50 PDT; processing completed, build 9 Testing in RELAY Development, test notes Saved; external build 2 still Waiting for Review |
| Native Cognito login | Login page opened with PKCE; **NOT TESTED to completion**, awaiting operator sign-in/MFA |
| Native microphone/WAV picker, phone cloud UI, native refresh/recovery | **NOT TESTED**; implementation/builds are not end-to-end UI evidence |
| Public HTTPS Swift client → real AWS writes/audio | **PASS**, text and reviewed-text requests, WAV upload/Transcribe, Bedrock proposals, lost-response replay and idempotent dispatcher updates |
| Independent DynamoDB readback | **PASS**, both new results and three-event histories; counts 17 requests / 3 audio jobs |
| Inventory reservation/decrement/transfer | **NOT IMPLEMENTED**; reported completion is a human progress event |
| Physical offline A–E, separate encounters, return receipt, router-independent path and repeated-failure metrics | **NOT TESTED** in this update |

Hardware remains iPhone 15 Pro Max / iOS 27.0.1 (24A446), iPhone 16 / iOS 26.2
(23C55), M3 Pro Mac. The previously tested AWS request
`REDACTED-ID-9d0de59831f3` remained `ready_for_review` over public HTTPS.
No discovery or wireless-latency metric was measured. Initial requester-B read
returned 401 because its token was expired; that observation does not establish
cross-account isolation with a valid token.

Follow-up by the existing AWS task refreshed requester-B through its existing MFA
and held the token in memory: B profile/directory 200, A's request/history 404,
dispatcher inbox access 403. Those valid-token isolation checks passed with no
shared token/configuration changes or new paid inference. See
[public HTTPS isolation evidence](evidence/https-isolation-build-9.json).

Subsequent public-URL Swift HTTP tests created typed request
`REDACTED-ID-5aa92435dab9`, transcription
`REDACTED-ID-81f7b3f5d045`, and explicitly reviewed-text request
`REDACTED-ID-ed8840839a4b`. The raw synthetic transcript again said
“Sheltering needs 2 water packs.” The agent explicitly corrected it to
“Shelter A needs 2 water packs.” Both Bedrock proposals identified water_packs,
quantity 2, unit pack, allocation_authorized false. Replayed acceptance and three
dispatcher event commands retained one logical request and three history events.
Independent DynamoDB reads confirmed these records and updated counters **17/30
requests, 3/5 transcriptions**. This remains shared-client CLI evidence, not native
browser sign-in, microphone, reviewed-text UI or physical-phone evidence.

New evidence: [public HTTPS text/audio](evidence/swift-https-aws-build-9.json),
[reviewed submission](evidence/swift-https-reviewed-aws-build-9.json),
[durable AWS readback](evidence/aws-readback-build-9.json).

Build 9 adds the bundled HTTPS address and validated WAV import (mono PCM16,
8/16 kHz, ≤60 seconds, ≤2 MiB); macOS uses user-selected read-only file access.
A private local helper displays existing synthetic credentials/current MFA for
the operator without logging them; it is not exposed through the tunnel. It
expires after two hours. No credentials or raw phone databases are committed.

Reproduction and current runtime limits: [DEMO_HOSTING.md](DEMO_HOSTING.md).
Evidence: [HTTPS checks](evidence/https-tunnel-build-9.json),
[phone preservation](evidence/physical-build9-install.json),
[Swift tests](evidence/automated-tests-build-9.txt),
[backend tests](evidence/backend-tests-build-9.txt),
[upload](evidence/testflight-upload-build-9.json).

## 2026-10-24 — build16 candidate: plain UI, streaming speech and demo hostname

This checkpoint is software/online testing, **not physical offline wireless
verification**. Physical phones were locked and were not updated in this session.

- Swift tests: **55 passed**; backend tests: **78 passed**, one dependency warning.
  Added eventstream CRC/framing, authenticated live session, final persistence,
  cached replay, cancellation/malformed audio/disconnect, session limits and crash
  expiry, partial replacement, retained WAV, old audio-job decode, and endpoint
  migration preservation/conflict tests.
- Native iOS Simulator and macOS Debug targets built. The plain UI uses bold
  system type, white backgrounds, outlined controls and a brown active accent.
  Text-size and contrast preferences are functional; request drafts survived a
  simulator restart. Final layout review remains in progress with this checkpoint.
- Actual native Swift→custom HTTPS hostname→Mac→AWS Transcribe synthetic streaming
  **PASS**. ID`REDACTED-ID-7356603b1bf8`; input1.824s; first partial
 2108ms; durable completion3663ms; same-ID replay used the persisted result.
  These are one sample, not physical mic/noise/radio or reliability measurements.
- HTTPS`relay.stepcheck.app` **PASS**: valid TLS, both enrolled account roles and
  subjects correct, no-store / CloudFront cache misses, anonymous request401.
  Original website/mail DNS preserved. Backend still depends on this Mac and its
  live Quick Tunnel; no PC or Lambda deployment is claimed.
- Application caps preserved usage and increased to100 requests/20 audio jobs;
  four concurrent live streams, one per account. Actual AWS quota report is
  retained separately from these application caps.
- Unified encrypted cloud/nearby shelter requests and the two-requester/Mac
  rehearsal are still pending at this checkpoint. Existing plaintext chat is
  not made confidential by this streaming/HTTPS work.

Raw safe evidence: `docs/evidence/streaming-20261024/`. Private enrollment files,
AWS credentials, signed URLs and raw private account data are excluded.

Follow-up verification in the same build16 worktree:

- Phone-size UI verified at Normal and Largest text sizes; high-contrast preference
  changes outlines. Primary buttons/tabs are accessible, keyboard focus has an
  explicit Done action, and the final bottom bar does not cover Review request.
- Real online UI rehearsal: iPhone17 Pro simulator → custom HTTPS API → Mac
  coordinator. Synthetic request`REDACTED-ID-9f9e777b271a` received a
  Bedrock preview (water packs, quantity2), was sent, and appeared in the Mac inbox.
  Coordinator reserved2, requester showed approval, coordinator confirmed handover,
  requester showed fulfillment. Mac stock changed from10 available/0 reserved/10
  on hand to8/0/8. This is a synthetic ledger workflow, not actual aid delivery.
- Inbox responses now include authorized history/reservation snapshots in the
  existing batch read. Native sync focuses on queued mutations and the open request;
  it no longer rotates through every old open request. Full78 backend and55 Swift
  tests passed after this change; the focused batch projection test also passed
  after adding history/reservation assertions.
- Loopback TCP experiment **PASS**, including interrupted transfer/retry, duplicate
  control, two real carrier process restarts and reverse receipt. Message
 `REDACTED-ID-e0113c7730a5`, receipt
 `REDACTED-ID-274a3419238a`. Physical A–E remain **NOT TESTED** here.
- AWS login credentials refreshed automatically via the login provider (observed
  expiry advanced from10:44 to10:54 UTC). No console credential bypass or new IAM
  access was used. API listener is now PID77564; worker75645/tunnel44716 remain.
