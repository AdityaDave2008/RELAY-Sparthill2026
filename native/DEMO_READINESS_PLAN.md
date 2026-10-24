# RELAY overnight implementation and acceptance plan

User objective: follow the attached plain, high-contrast reference; add streaming
ASR; make the demo work with two requester iPhones and this Mac as a shelter;
inspect Namecheap domains and PC hosting options; verify on Mac/simulators while
phones are locked. Work stays in this thread. No coordination with the other chat.

## Required outcomes and evidence

1. Reference UI: white/black, bold sans-serif, strong borders, large usable controls,
   restrained brown accent. Implement real Normal/Large/Largest and high-contrast
   preferences. Verify phone-size screenshots and Mac screens, keyboard, overflow,
   review, request inbox and inventory. No placeholder-only UI.
2. Streaming speech: authenticated bounded session, PCM microphone streaming,
   incremental/final results, editable transcript and explicit review/send. No AWS
   long-lived credentials in the app or logs. Test frame codec, partial replacement,
   finish/cancel/disconnect, limits and actual AWS synthetic speech via the native
   client. A prerecorded WAV streamed in chunks proves transport, not phone mic.
3. Shelter delivery: a saved shelter destination, same request workflow for cloud
   and nearby encounters, durable dedup/receipts and native Mac shelter inbox.
   Keep relay acceptance distinct from shelter receipt and staff approval. Precise
   coordinates must not be sent through existing plaintext relay messages. Verify
   two simulated requesters and Mac shelter, restart/loss/retry and return receipts.
   Physical infrastructure-independent acceptance remains an operator test.
4. Runtime: inspect actual AWS permissions, configured demo caps and available
   service quota evidence; report the difference. Keep bounded demo usage and
   actionable errors. Verify API/auth/worker health, restart instructions and
   stable hosting before declaring it ready. Prefer the always-on PC only if it
   can actually be reached/configured; do not invent access or move to unrelated HPC.
5. Domain: inspect the signed-in Namecheap account in Chrome. Choose an unused
   subdomain, preserve existing website/mail records, and verify HTTPS and API
   semantics. A domain is not hosting, and a redirect/invalid certificate is not
   a working API. Record any external account/access gate honestly.
6. Deliver: build iOS/macOS, run focused unit/integration tests, preserve phone
   identities/data, commit/push source, document an exact morning rehearsal and
   known limitations. Do not mark the goal complete based on builds or mocks.

## Current evidence / decisions

- Starting source26352e3, build15, clean integration worktree. Prior result49Swift/
  67backend tests, with separate physical radio acceptance still unverified.
- Reference image inspected: black/white bold interface, brown active tab, explicit
  three text-size choices and high-contrast toggle. It supersedes build15's serif theme.
- Namecheap account is signed in in Chrome. Domains observed:stepcheck.app and
  glpmate.app. DNS records/nameservers not yet inspected or modified.
- SSH config contains GPU research hosts, no identified personal PC. Do not use
  those hosts for this backend. Mac API61517/worker54245/tunnel44716 confirmed live.
- Cloud and P2P shelter paths are currently separate; this is real remaining work.
- Existing streaming permission, AWS quotas, domain setup and PC reachability:
  pending targeted checks.

## Work log

- Initial goal turn: progress—reference inspected, repository/runtime/browser state
  verified and this implementation/acceptance plan created. No goal completion claim.


### Current checkpoint — 2026-10-24 03:40 PDT

- Actual AWS streaming and native Swift client pass. `RelaySpeechCheck` sent a
  1.824 s synthetic WAV over the complete `https://relay.stepcheck.app` route.
  Ready 956 ms; first partial 2108 ms; durable complete 3663 ms (one sample,
  includes realtime pacing). Same-ID reconnect reused the persisted result.
  Transcript misheard “Shelter A” as “Sheltering”; human review is still needed.
- 55 Swift tests and 78 backend tests pass. Native iOS/macOS builds pass before
  the latest tab visibility adjustment. UI test found and is fixing bottom-bar
  overlap/duplicate native tab bar. Largest text, real high contrast toggle,
  saved draft, explicit Done and Settings navigation have been exercised.
- `relay.stepcheck.app` has a validated ACM certificate and CloudFront
  E35672O7SGUTD2 → du685az67zetl.cloudfront.net → existing HTTPS Quick Tunnel.
  Only new `relay` and ACM validation CNAME records were added at Namecheap.
  Existing website/mail records and nameservers remain unchanged. Auth forwarding,
  no-store / cache misses, and unauthenticated 401 were verified. This is still
  Mac-hosted; the custom domain does not eliminate the origin/tunnel dependency.
- AWS service quotas: 25 standard concurrent streams, 25 starts/sec; in-region
  Nova Lite 2,000 requests/min, 4M tokens/min. App limits now 100 requests and
  20 transcription allocations, four simultaneous live sessions, one per user.
  Counters preserved: 20 requests / 7 transcription allocations at this checkpoint.
  Two direct AWS probes (silence/synthetic speech) additionally ran outside that
  application counter. No quota increases or IAM changes were made.
- Main runtime upgraded: API75644, worker75645, logs `/tmp/relay-demo16-serve.log`
  and `/tmp/relay-demo16-worker.log`; tunnel44716 unchanged. Candidate18789 remains
  temporarily running. Mac caffeinate is bounded to eight hours from ~03:19 PDT.
- Existing cloud endpoint migration copies queued requests/drafts/audio references
  and pending inventory operations atomically after same-account verification;
  preserves old scope as backup; tests reject conflicting content and preserve
  newer target state. New build number16, not uploaded/installed on physical phones.

### Next implementation gate: unified shelter delivery (not yet implemented)

- Register stable device signing/encryption public keys through authenticated API;
  authorized coordinator assigns its device as a shelter receiver. Cache the
  receiver address/keys in the existing authorized directory before disconnecting.
- Same immutable CloudSubmission ID/content goes to cloud and encrypted nearby
  envelope. Use CryptoKit X25519/HKDF/authenticated encryption + P256 sender
  signature over exact submitted bytes. Never forward bearer tokens or plaintext
  precise coordinates. Old carrier protocol can retain the opaque payload.
- Receive/decrypt/validate before final application receipt; persist atomically.
  Sign shelter receipts and require the pinned shelter key when recognizing new
  sealed-request delivery. Existing plaintext chat stays explicitly unverified.
- Mac merges cloud/nearby rows by request ID. Authenticated gateway ingest validates
  the registered origin key/current membership and submits under that origin;
  replay through HTTP and nearby must not duplicate requests or reserve inventory.
- Offline local receipt is distinct from cloud acceptance/staff approval. Inventory
  continues to require the authoritative online ledger. Offline unknown sender
  identity is pending verification until registered signature is checked by API.
- Rehearse two requester simulators plus Mac, separate carrier restart and reverse
  receipt tests. Phone/radio/infrastructure-independent acceptance remains morning
  physical operator testing, not inferred from simulator/loopback results.

- 03:50 PDT checkpoint: phone layout verified with no duplicate/overlapping bar;
  real UI request/Bedrock/approval/handover rehearsal passed. Synthetic request
 `REDACTED-ID-9f9e777b271a` completed and Mac water stock is8 available,
 0 reserved,8 on hand. Loopback TCP restart/retry/reverse-receipt controls passed.
  Native busy time was reduced by removing repetitive old-request polling and
  hydrating inbox history/reservations in one authorized batched response. API
  updated to77564. Mac debug auth is now scoped to the binary resource signature
  to avoid ad-hoc Keychain prompts between development rebuilds; Release still
  uses the stable native session service. Updated Mac build with this last auth
  tweak still needs rebuilding/enrollment before the next native rehearsal.


### 04:12 PDT — unified bridge implementation checkpoint

- Commit924d12d is pushed to feature/cloud-integration / PR2. Later bridge changes
  are still uncommitted and need native integration validation before release.
- Added CryptoKit X25519/HKDF/ChaChaPoly envelopes and P256 signatures. New requests
  use one immutable CloudSubmission ID across HTTP/nearby. SQLite atomically stores
  decrypted destination content and a signed receipt; carriers only store ciphertext.
  A plaintext forged receipt cannot complete an encrypted request. Existing IDs,
  plaintext chat and queues remain compatible; encrypted requests are excluded
  from personal chat projections.
- Device keys persist in an app-sandbox file (0600; iOS file protection), not a
  Secure Enclave or production security claim. Receipt proves destination-device
  persistence, not authenticated staff approval. Offline sender identity is pending
  server verification. Enrollment is scoped by account subject AND stable device
  ID, so changing accounts preserves earlier signed ownership and device routing.
- Gateway API registration/receiver assignment/ingestion checks current membership,
  receiver revision, exact-byte P256 signature and registered origin keys. It
  submits under the original requester. Direct upload/gateway replay deduplicate.
- 61 Swift tests pass (six new encryption/carry/restart/forgery/key-persistence
  tests); 87 backend tests pass (nine new gateway/enrollment/auth/duplicate tests).
  Native CryptoKit→Python fixture gateway smoke passed:
  REDACTED-ID-0e448db07b2a. This is fixture API verification, not live
  AWS or physical wireless evidence. Current native macOS/iOS builds pass.
- App now registers keys, Mac auto-selects itself when a shelter has no receiver,
  caches receiver keys, queues encrypted nearby copies from the main request form,
  reconciles received requests into the coordinator inbox, and ingests through the
  signed gateway. It distinguishes relay saved / verified shelter receipt / cloud
  acceptance / staff action. These app changes still need the native rehearsal.
- Added an explicit Demo tools “Pause cloud delivery” control for software route
  isolation. This does not prove router-free connectivity and must not be reported
  as physical offline radio success. Need finish gating all relevant cloud actions
  and verify the pause/reconnect path.
- Preparing iPhone17 Pro simulator (RequesterA), iPhone17 Pro Max simulator
  (RequesterB), and existing Mac coordinator. Live RequesterB membership was
  explicitly extended to ShelterA for this two-requester/same-shelter synthetic
  demo; fixture RequesterB remains isolated to ShelterB for authorization tests.
- Remaining: run real native nearby/gateway/receipt workflow, exercise carrier
  restart separately, refresh signed builds after final changes, update evidence,
  portable hosting/restart guidance, morning operator steps, and distribution.
  Physical phones remain untouched/locked; no physical wireless success claim.


### Final checkpoint — 24 October, 05:27 PDT

- Plain-reference UI and live speech are implemented;62 Swift/87 backend tests pass.
- Encrypted native requester→carrier→Mac shelter and signed return receipt passed
  on two iPhone simulators plus Mac, with two carrier restarts and A/C never active
  together. Cloud resumed under the same request ID; foreign carried content stayed
  outside the carrier's personal inbox. Three further TCP failure trials passed.
- Build16 uploaded04:42:55PDT; final build17 uploaded05:25:17PDT with the last
  successful-refresh error-label fix. Mac/simulator builds pass. Apple processing
  reported; external tester availability is unverified. Phones were disconnected.
- Final cloud preflight exposed expired AWS refresh credentials. Renewed the SAME
  WSParticipantRole/Participant in account928489693154 via the existing Workshop
  Studio session, restarted API86528/worker86529, retained tunnel44716. No IAM
  changes or store/counter reset. Preflight, live native Transcribe and Bedrock
  worker processing pass again. App counters24/100 requests,8/20 transcriptions.
- `relay.stepcheck.app` verified through CloudFront to the Mac; PC migration is
  documented but unavailable without a configured PC connection. Keep Mac powered,
  awake and online for cloud. The current keep-awake session ends about11:19PDT.
- MORNING_DEMO.md and TEST_RESULTS.md contain exact rehearsal steps/IDs/limitations.
  No physical no-router, physical mic/GPS, range/background or disaster-resilience
  claim. No other chat or agent was contacted. No HPC/Dreamer files were changed
  except the required parent session-log entry.


### Build19 follow-up — approximately08:00PDT

User requested robust transcript extraction, faster replies, medicines and urgency.
Implemented/verified: structured Bedrock tool output with field-level grounding,
manual urgency and unit corrections, medicine staff-review requests, one-slot preview
acceleration,3s focused snapshots/8s inbox polling, immutable/pending-write merge,
legacy fractional timestamp compatibility, same-ID gateway/direct preview race fix.
66Swift/99backend tests and TCP control pass. Three real AWS previews2.265–3.498s;
two API reply POST/read samples1.171/1.211s. Native simulator/Mac manual override,
review/send and automatic reply refresh pass. Both physical phones installed/launched
build19 in place; old data preserved. TestFlight19 uploaded07:56:48PDT; external
availability unverified. API3671/worker2040 use private aws-config-demo18; tunnel44716
unchanged. No physical no-router acceptance or real phone mic/GPS quality claim.
