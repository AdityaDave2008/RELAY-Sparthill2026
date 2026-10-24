# RELAY physical acceptance plan

**Build22 resident profile/sharing:** [procedure and privacy boundary](docs/RESIDENT_SETUP.md#test-procedure).
Record required name/language, photo Save/restart, first-run Skip, guide navigation,
per-request sharing defaults/selection, coordinator visibility, login, account
separation, larger text and clearing disposable profile data separately.
Use synthetic profile values. Installing this UI update is not a wireless test.

**Build20 alerts/location extension:** follow the reproducible steps in
[Announcements and shelter information](cloud/docs/ANNOUNCEMENTS.md#reproduce).
Record cloud incident publication, each phone's downloaded cache, read-aloud audio,
withdrawal, cache across restart, manual-location alternative and distance separately.
New alerts use HTTPS; cached alerts are not evidence of P2P announcement delivery.
Real GPS accuracy and audible TTS on both physical phones still require observation.

**Current cloud/voice/location/coordinator-inventory procedure:** [MOBILE_TEST.md](MOBILE_TEST.md).
Use the current role-specific interface. The older Cloud tab references below are
historical; engineering controls now live in Settings → Demo tools.

For the current internet/cloud flow, follow [DEMO_HOSTING.md](DEMO_HOSTING.md).
Cloudflare hosting and AWS results do not satisfy any physical offline criterion
below. Preserve separate evidence for native login, transcript review, request
creation, dispatcher history, cloud reconnect and each offline radio encounter.

Build 6 navigation: **Help → gear** opens Tools, and **Help → Nearby devices** opens
discovery. References to Chats mean the Messages tab. All original A–E criteria apply.

## Historical shelter-code test extension (build6)

1. On receiver C, open Shelters → Create shelter on this device. Save a synthetic name
   and area. Open its entry, copy/share the code and import that exact code on A.
   Confirm the shelter ID and receiving UUID match; B needs neither directory entry
   nor staff permission to carry the envelope. These labels are not authenticated.
2. On A, tap Request help here, enter synthetic details, quantity/unit and location.
   Leave people blank and confirm review says Unknown. Leave networking paused.
3. Wait for Draft saved on this device, terminate/relaunch A, and verify the same
   fields return. Review and save. Record the generated request UUID. Verify the
   form resets only after saving and the request says Locally saved — queued.
4. Execute the isolated A/B, B restart, B/C, B/A encounters from tests B/C below.
   The message's destination UUID remains C; its content also records the shelter ID.
5. C's Requests → Device inbox contains one request. B's My requests/Device inbox
   and all personal chats exclude this carried request. C creates one receipt.
6. A displays Final destination receipt received only after the return receipt
   arrives. Staff progress remains No staff update recorded. Do not count a receipt
   as assignment or fulfillment. Repeat D/E with the structured request.
7. Retry an import of the same code (one directory entry); a conflicting code with
   the same shelter ID must fail without changing its receiving-device address.
8. Repeat with largest text and keyboard visible; verify Done, review, save, and a
   second request remain usable. No cloud, verified staff roles, or production
   confidentiality is implied by these controls.

Record each result as **PASS / FAIL / NOT TESTED**, never infer wireless success from compilation, simulator behavior, a common LAN, or loopback. The actual execution record is [TEST_RESULTS.md](TEST_RESULTS.md). This plan has not been physically executed in the current session.

## Preparation and evidence sheet

Use two physical iPhones (A, B) and an Apple-silicon Mac (C). Install per [README.md](README.md). Write down:

- Test/date/operator; app source revision; hardware model, OS build, Xcode/SDK; signing team outcome (no credentials); Local Network/firewall prompt decisions.
- Persistent device UUID and role on each device. In build 3, role changes reconnect active networking; use Pause connections to deliberately stop an encounter. Record C's UUID before separating devices; manually type/paste it at A. Discovery need not happen between A and C.
- For every encounter: physical location/separation and which apps/radios are active; Wi-Fi association, cellular, hotspots, tethering, Ethernet, VPN and internet state on **every** device. Capture before and after.
- Start/discovery/connection/transfer/ACK timestamps, actual message/receipt UUIDs, `PATH`, `PERSISTED`, `STORAGE_ACK_RECEIVED`, `RECEIPT_CREATED`, `FINAL_RECEIPT_RECOGNIZED`, failure and duplicate lines. Use Tools → Open diagnostics → Copy complete diagnostic log on each app. Also retain screenshots of the queue before and after B's restart.
- Whether A–C are out of range or merely application-blocked. State which path evidence was collected and exactly what it supports. Leave unavailable metrics blank; record retries/timeouts as failures rather than dropping samples.

Use synthetic text only. Keep device clocks reasonably aligned; messages default to a 24-hour TTL. Do not uninstall between encounters; that can erase queued messages and change device UUIDs. Keep apps foreground and devices awake during each encounter; iOS background discovery is out of scope.

## Infrastructure-independent setup (required for every physical PASS)

1. On both iPhones, enable Airplane Mode, then explicitly re-enable Wi-Fi and Bluetooth in **Settings**. Check cellular is off. Keep Personal Hotspot off. Airplane Mode alone is not proof that required radios remain on.
2. Disconnect/forget the current conventional Wi-Fi network and prevent automatic reassociation for the test. The Wi-Fi radio must stay **on**, with no ordinary SSID selected. Do not create a common hotspot or ad hoc infrastructure network. Do not rely on Control Center's ambiguous Wi-Fi button state.
3. On the Mac, leave Wi-Fi and Bluetooth enabled but disconnect from ordinary Wi-Fi; turn off autojoin for nearby known networks for the duration. Unplug Ethernet/docks/tethering; disable Internet Sharing and personal hotspots. Disconnect USB phone cables after deployment. Remove VPN/virtual/tether interfaces as possible alternate paths; record the state.
4. Verify all three devices lack internet access. A failed website load alone is insufficient: an isolated conventional router still violates the test. Also verify lack of common AP association and other infrastructure paths. Record settings views and Mac interface/route observations. Do not infer an iPhone's state from the Mac.
5. On the Mac, collect read-only observations before/during/after encounters. Determine the Wi-Fi interface rather than assuming `en0`:

   ```sh
   networksetup -listallhardwareports
   networksetup -getairportnetwork en0 # replace en0 with the actual Wi-Fi interface
   ifconfig
   netstat -rn
   scutil --nwi
   ```

   Some macOS versions redact SSID information. If so, record that limitation and verify association in System Settings; absence of a printed SSID by itself is not proof.
6. Preserve RELAY's actual NWConnection `PATH` logs. If available to the operator, capture only the test session's traffic on the peer-to-peer interface using Wireless Diagnostics or a scoped `tcpdump` capture. Inspect available capture interfaces first (`tcpdump -D`). An operator may run `sudo tcpdump -i awdl0 -nn -s 0 -w relay-awdl.pcap 'tcp'` **only if that interface exists**, and stop it promptly after the encounter. Correlate the test endpoints/ports and message timing. Captures can contain other nearby traffic; keep test data synthetic and avoid sharing unrelated capture content. Do not disable SIP/security settings or force undocumented interfaces to manufacture a result.
7. Require the combination of verified isolation, physical endpoints, and actual transfer evidence. If the chosen path cannot be established confidently, report **path UNVERIFIED**, even if the message arrived. `includePeerToPeer`, `usesInterfaceType(.wifi)`, a Bonjour result containing `awdl0`, and link-local addresses alone do not certify a peer-to-peer data path.

## A — Direct physical offline connection (P0)

1. Keep C's networking paused. In Tools → Advanced relay test, set physical A to Sender A and physical B to Relay B, disable Force A → B → C for this direct test, and record both UUIDs.
2. Complete the isolation checklist above. Permit RELAY's normal Local Network/firewall prompts. Tap Connect on A and B. Record the time from starting the second peer to discovering/connecting.
3. In Chats → New chat, select B or enter **B's UUID**, then send from the fixed bottom input. Record its generated UUID; do not hardcode the label M001 as a wire ID.
4. Require B's `PERSISTED`, a single logical request row at B, A's `DESTINATION_STORED` ACK, and the separately generated receipt if it returns during this encounter.
5. Stop networking, terminate/relaunch B, and inspect the same request to establish durability.

**PASS:** a message moved between the two physical phones, committed at B, under documented no-internet/no-infrastructure conditions with supporting path evidence. Common Wi-Fi success is a debugging control, not Test A success.

## B — Three-device store-carry-forward (P1)

1. Select Sender A / Relay B / Receiver C. For a close-range test, leave **Tools → Advanced relay test → Force A → B → C** enabled on all devices. Label the result **logical relay**. This drops A–C at handshake before inventory/message traffic; it does not disable discovery or radio reachability.
2. Record C's UUID at A. Stop C's networking, start A and B, and repeat the isolation checks.
3. A creates `SYNTHETIC M001: Shelter A needs 20 water packs`, addressed to C. Record the actual UUID M.
4. Wait for B's `PERSISTED id=M`, one B request row at hop 1, and A's `RELAY_STORED` ACK. A must show accepted by relay, **not final delivered**. C must not yet contain M.
5. Stop A's networking; verify disconnect logs. Move A away if possible. Terminate B (force-close on iOS), relaunch, and verify the same device UUID and M remain **before** reconnecting. Capture this state.
6. Start B and C, with A still stopped/out of range. B should advertise/discover/connect and forward M without another Send action. C must persist M at hop 2 and generate receipt R atomically. Record R and its `original_message_id=M`.
7. Wait until B has persisted R. A must still not show final receipt while disconnected.

**PASS for logical relay:** M arrives at C after B's disconnected restart, with A inactive, matching origin/destination/ID/payload and a separate receipt. This is not proof of physical A–C separation.

**Separate out-of-range variant:** repeat with A and C genuinely out of direct radio range, forced routing **off on all three**. Carry B between the locations. Record distance/layout and an A–C direct-connect negative control with B inactive; do not equate a failed connection alone with a measured radio range. Ensure no shared AP covers the locations. Report this variant independently. If impractical, mark it NOT TESTED.

## C — Return receipt (P2)

1. Starting after Test B, verify B has durable R (not merely a send-attempt log at C).
2. Stop C, disconnect B, optionally terminate/relaunch B again, then bring B back to A.
3. Start A and B. B should forward R automatically. Require A's `PERSISTED id=R` and `FINAL_RECEIPT_RECOGNIZED id=R original=M`.
4. A's original M row must change to **Final destination receipt received** and remain so after relaunch and duplicate receipt transfer. Compare to the earlier **Accepted by relay** status.

**PASS:** separate C→B and B→A encounters carry R back and correctly associate it with M. An ACK from B alone does not pass C.

## D — Duplicate delivery (P2)

1. During an A↔B or B↔C encounter, find M's stored row on its sending/forwarding device. Open **Tools → Open diagnostics** and press the matching **Retransmit [ID]** button three times. Keep the same UUID; creating new messages is not a duplicate test.
2. Verify `FORCED_DUPLICATE_TEST`/transfer logs and matching `DUPLICATE_SUPPRESSED` at the receiver. Count logical rows in the UI/exported store.
3. Require exactly one M request and one destination-generated receipt for M. Delivery/receipt state must remain intact. Repeat with a receipt forwarded by B to A.

**PASS:** repeated transmissions are visible, with one durable logical request/action and preserved delivery state. Document number of attempts.

## E — Interrupted transfer and retry (P2)

1. Use a fresh message. While the sender is disconnected, press **Interrupt next transfer midway**; then save the message addressed to the intended destination. Connect the next peer.
2. The next eligible message frame is cut in half and its connection closed. Verify `FAULT_INJECTION`, `PARTIAL_FRAME_DISCARDED`/`STREAM_END partial=true`, and no persistence/ACK for that fresh ID at the receiver.
3. The sender must retain the message and show queued/awaiting durable ACK. With discovery still active, automatic reconnect/retry should follow. If testing manually with Stop, press Start to re-enable discovery.
4. Verify a later complete transfer commits once and receives the appropriate storage ACK. Final receipt requires the destination encounter; a relay retry cannot falsely mark final delivery.
5. Repeat with physical interruption (range loss, app termination during a larger synthetic text transfer) and log whether the receiver actually saw partial data. Small requests may complete before an operator disconnects; do not count those as interrupted-frame evidence. Also test loss **after commit but before ACK**, which should deduplicate on retry.

**PASS:** no false final delivery under interruption, durable source queue, successful later retry, and no repeated application action. The fault injection verifies protocol interruption on the physical link; range-loss characterization is a separate measurement.

## Failure investigation and repeated trials

Before switching technology: inspect identical Bonjour service entries, permission state on both OSes, firewall prompts, listener/browser readiness, foreground activity, device/SDK support, radios, and automatic Wi-Fi association. Export logs before restarting. Try a common Wi-Fi network only as a clearly labeled control. A working LAN control isolates framing/app problems but does not pass offline acceptance.

Run at least 30 independent **physical** interrupted encounters per link direction, record every attempt/failed discovery, recovery delay, delivery latency (with clock assumptions), duplicate counts, and terminal result. Measure distributions and denominators, not only successes. Add longer carry intervals, device reboot, low battery, low storage/full quota, changing clocks, multiple relays, mixed OS versions, range/obstruction, and background/lock behavior. Power-loss durability, authenticated identity, confidentiality, malicious peers, and realistic congestion also need separate evaluation before any disaster-resilience claim.

## Device names and personal-chat isolation (build 5)

1. On each device, use Tools → Edit name and choose distinct synthetic test labels. Connect peers and verify those names in Nearby and New chat. Names do not change which device can send or receive.
2. Rename one connected peer; wait for its reconnect. Verify the existing conversation updates its title without creating another thread or changing its UUID. Restart and verify the name persists.
3. Give two devices the same name. Verify their short IDs differ and selecting one still addresses only its UUID.
4. Send A → C through B. A should show a sent bubble; C should show a received bubble. B should have no personal chat for that message. In B’s Tools → Open durable queue, verify “Forwarding copy · not addressed to you,” destination metadata, and no payload preview even when expanded.
5. Distinguish UI separation from security: this prototype still carries plaintext and does not authenticate names. Never use private or emergency data for this test.


## Shelter removal and code import (build 7)

1. With connections paused, create a synthetic shelter on B. Open it and Share
   shelter code to A before the offline encounter. Copy alone changes only B's
   clipboard. On A, tap Import shelter and paste the full `RELAY-SHELTER-1:` code.
2. Require the expected name, area and receiving-device preview, then Import.
   Verify one entry appears. Reimport the same code and require one logical entry.
   Wrapped code with whitespace should work; truncated/foreign codes must show an
   error and disable Import. Connect is unnecessary for these local operations.
3. Import a shelter received by A itself. Require the self-receiver explanation;
   it remains in Shelters but is excluded from Help's outgoing destination list.
4. Create an unsent draft addressed to B's saved shelter. Remove that shelter via
   its detail and confirmation. Verify it disappears from active destinations,
   draft text remains, and its destination clears. Restart and repeat inspection.
5. Expand Removed shelters and Restore. Verify the same shelter ID/details return.
   Restore by identical code import as a separate test. A conflicting code with the
   same ID must not change the receiving device, even while the entry is removed.
6. Remove a shelter after submitting a request. Verify its request and final
   receipt history remain. Queued messages continue delivery: directory removal is
   not request cancellation and does not revoke shelter copies on other devices.

Run on both physical phones in addition to automated/native Mac UI controls.
Record per-platform results; installation alone is not a physical UI test.


## Build 8: conversations, cloud and reviewed voice

1. With nearby connections paused, receive/open a synthetic help request. Reply
   and choose a reported progress value. Require locally queued state, an empty
   reusable composer and Done. Restart and require the same reply ID/thread.
2. Connect the recipient in a separate encounter. Require exactly one reply in
   that request thread and its independent delivery receipt. Personal chat must
   exclude request-update envelopes. Repeat with duplicates and a relay restart.
3. After the HTTPS API is deployed, sign into the native app with an enrolled
   Cognito account/MFA. Verify state validation, cancel/retry, Keychain restart,
   token refresh, sign-out and different-account isolation. Refuse HTTP URLs.
4. Link a local shelter to an authorized cloud inbox. Review a request with Also
   queue for cloud selected; kill/restart after local save before upload. Require
   the same request ID/body to sync once. Interrupt after server commit before the
   reply; retry must return the same request. Cloud failure must preserve P2P.
5. Dispatcher loads only its allowed inbox, replies and updates progress. Reuse
   command ID; require one event. Race two expected revisions; require a conflict.
   Requester cannot assign staff progress and unrelated users cannot read history.
6. Record synthetic speech on a physical phone. Check denied microphone permission,
   60-second cutoff, WAV format, interrupted upload and app restart. Resume the same
   transcription job. Correct words/quantities, explicitly apply to Help and review
   before submitting. Require reviewed_transcript reference and same request ID.
7. Verify signed-out and offline behavior. Cloud/AI failures must never fabricate a
   proposal, delivery receipt, allocation or fulfillment. A carried request is not
   uploaded under the carrier's account. The enrolled shelter gateway verifies the
   original sender signature and submits under the original requester's ownership.
   Verify direct/cloud replay remains one logical request.

Separate CLI/fixture/AWS-loopback evidence from native device UI and physical radio
tests. No public HTTPS or native cloud-flow PASS until those exact tests run.
