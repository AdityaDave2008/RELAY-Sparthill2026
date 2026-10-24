# Resident profile, sharing and walkthrough — build22

Residents use **Ask for help / Requests / Alerts / Settings**. The Help page begins
with its title and a small question-mark guide button. Personal details live in
Settings; delivery status lives with the request. Supply buttons retain emojis and
readable accessible labels: 💧 water, 🥫 food, 🛏️ blankets, 💊 medicines, 📦 other.

## Login and first use

Signed-out users see a dedicated RELAY email/password screen. The existing backend
account assigns the resident or coordinator workspace; there is no public sign-up
or client-side role switch. Each resident needs a distinct organizer-issued account.
Sign in online once and cache shelter receiver setup before testing offline use.
A returning cached account can open its local workspace without a fresh online login.

Residents see optional setup and a six-page walkthrough once per account/device.
**Display name and preferred language are required when saving a profile.** Photo,
age, height, weight, blood group, allergies, conditions, medications and support
needs are optional. Skip for now remains available so setup does not block an urgent
request. Unknown health information must remain blank. The encouragement text
explains how selected details help staff understand a request.

The guide covers speech/AI review, shelter selection, delivery versus staff approval,
nearby carrying, alerts and accessibility settings. Reopen it from the question-mark
icon beside Ask for help or from Settings. Editing a profile happens in Settings.
Completed/skipped setup does not repeat on restart. Existing build21 profiles load
without the new fields; choose a language when next saving them.

## Photo and local profile

The system Photos picker grants access to the selected image. The app converts it
to a JPEG thumbnail of at most256px and24000bytes, re-encoding pixels without original
EXIF/GPS metadata. A photo stored only in iCloud may need internet to download.
Change and Remove modify the editor draft; Save persists it, Cancel discards edits.
**The photo stays local and is never attached to a request or shown to dispatchers.**

The profile is a Keychain generic-password item, isolated by app bundle ID and an
endpoint/account-subject hash, using `WhenUnlockedThisDeviceOnly` with synchronization
disabled. Profiles do not sync between devices. Signing out hides but retains the
matching account's profile. Clear saved personal details removes this local item
after confirmation. OS-controlled Keychain behavior means uninstall is not a reliable
profile-deletion mechanism. Mac ad-hoc development signing can trigger Keychain
access prompts after rebuild; production distribution needs stable signing.

## Explicit sharing with a shelter

Review request has **Share personal details with this shelter**, off by default.
Turning it on attaches name and preferred language. Two separate switches add
health details and accessibility/support needs. Review shows the exact selected text
before Send; a missing name/language blocks sharing until completed or disabled.

Sending freezes the selection into optional `requester_details` in the immutable
request. It is durably stored with the request, goes to the authenticated HTTPS
backend and/or inside the existing encrypted nearby envelope, and is readable by
the requester and authorized destination staff. Carrier phones see ciphertext.
Editing or clearing the local profile does not change or erase a previously sent
snapshot. This is a change from build21, whose profile stayed entirely local.

Attached profile fields are **excluded from the Bedrock extraction prompt**. Text
that the user explicitly types or dictates in the request still follows the existing
Transcribe/Bedrock workflow. Do not describe that request text as excluded from AI.
The photo has no wire field and the backend rejects attempts to attach one.

The profile itself stays outside the request SQLite store, but explicitly shared
snapshots are now part of the durable request records. The first-run metadata still
contains only setup flags. Old requests without details keep their original payload
shape/digest. Retries and direct/gateway delivery deduplicate the same frozen body.
Upgrade sender and receiving endpoints to22 before sharing details: older clients
do not display/preserve this optional field in typed caches. Existing message-size
limits remain; unusually long requests plus notes can require shortening before
an encrypted copy can be sent. There is no silent plaintext fallback.

Values are bounded and self-reported, not verified clinical records. The app does
not infer blood group, diagnose, prescribe, calculate BMI, or automatically prioritize
based on health history. Staff approval remains separate from delivery and AI.

## Test procedure

1. On build22, Settings → Photo & personal details. Use synthetic values, select a
   local test picture, set a display name and language, then Save. Blank required
   basics should show an error; health and photo can be omitted.
2. Restart the app. Reopen Settings: picture, language and other saved values remain.
   Change one value, Cancel, reopen: the original remains. Change/Remove photo and
   Clear are separate optional manual checks using disposable synthetic data.
3. Help should begin with Ask for help and the small guide icon. It has no Your
   details link or Cloud + nearby delivery text. Open the guide with the icon.
4. Create a short synthetic water request with a typed test landmark. Review:
   sharing must start off. Enable basic sharing, then health/support selectively;
   verify the exact preview and absence of a photo. Send once.
5. On the destination Mac/coordinator Inbox, open the same request ID. Verify only
   selected fields appear. Verify cloud acceptance and shelter receipt separately.
   Sending a profile does not approve stock or complete a request.
6. Sign out of a disposable simulator account: a dedicated login page replaces the
   workspace. Sign back into the same existing account: profile/history are retained.
7. Optional remaining checks: physical photo picker, largest text/VoiceOver, account
   isolation on one device, offline profile editing, unavailable Keychain and
   iCloud-only photo errors. Test physical radio conditions separately under A–E.

Build22 native UI testing used a synthetic avatar selected by the user in Simulator,
then Save/restart/reopen. A synthetic shared request reached the Mac with the expected
fields. Automated photo bounds/metadata, immutable snapshot, encryption, authorization,
legacy retry and AI-exclusion tests pass. See TEST_RESULTS and docs/evidence/build22.

## Replay the first-run demo — development build23

On an owned phone with the original DEBUG build23 installed, run:

```sh
bash scripts/replay_resident_setup.sh CORE_DEVICE_ID
```

This relaunches RELAY with `--relay-replay-resident-setup`. Once the current resident
account loads, only its `profileOffered`/`guideSeen` flags reset, once per explicit
launch. It returns to **A little about you**, then the walkthrough. Existing profile
values/photo, login, requests, messages, receipts and keys stay saved. Complete or
skip setup normally; ordinary launches do not replay it. Coordinator accounts are
unaffected. The launch option is excluded from Release/TestFlight builds. Installing
an update or simply restarting the app does not otherwise reset completed setup.
