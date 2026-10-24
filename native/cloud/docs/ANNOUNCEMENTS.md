# Announcements, shelter information and identity — build20

The new Alerts tab is present in both workspaces. A dispatcher chooses an
authorized publishing shelter, writes a title/body, selects Information,
Important or Urgent, chooses expiry (1/6/24 hours), reviews, then publishes.
Every enrolled account in that incident can fetch the notice, whether or not it
has created a help request. A dispatcher can withdraw notices from shelters they
are currently authorized to coordinate. Residents cannot publish, withdraw or
edit shelter information. This is incident scope, not an unrestricted global feed.

## Delivery and persistence

- `GET /v1/announcements`: authenticated, current incident only. Complete bounded
  snapshot with server `fetched_at`; no cross-incident enumeration.
- `POST /v1/announcements`: immutable UUID, publishing shelter, title, body,
  severity, timezone-aware expiry. Requires dispatcher role + shelter membership.
  One conditional transaction saves feed and operation digest. Retrying identical
  content returns the original/current result. Changed content under the same ID
  is a 409. Concurrent writes cannot silently overwrite one another.
- `POST /v1/announcements/{id}/withdraw`: expected revision; bumps revision and
  preserves the withdrawn notice. Same lost-response retry is idempotent.
- The bounded feed retains up to 100 unexpired entries, additionally capped at
  300KB of serialized payload. Publication prunes expired entries. API expiry is
  one minute to seven days. It does not consume AI/transcription allocations.
- The app persists the publication command before HTTP; uncertain publication
  offers retry with the same UUID/body. It does not silently republish an edited
  copy. An expired uncertain command can be cleared after fetching the feed.
- Feed, last refresh and read revisions are saved in SQLite metadata under a hash
  of endpoint + account subject. Account switching clears visible state. Reopening
  the same account offline restores its cache. Read markers are local to that
  account/device, not delivery/read receipts sent to dispatchers.
- Foreground refresh is attempted about every12s (the existing async sync loop can
  delay it); opening Alerts and Refresh trigger a fetch. This is not APNs and has
  no background delivery guarantee. Expired/withdrawn items leave the active list.
- Newly published notices and withdrawals **do not travel over the nearby relay**.
  Previously downloaded notices remain readable offline until their displayed
  expiry. An offline device cannot know about a later withdrawal. The UI shows
  last-check time and explicitly avoids equating an empty feed with safe conditions.
  Signed offline broadcast, trust distribution/revocation, persistent reconnect
  fanout and physical delivery tests remain future work.

## Read aloud

An explicit Listen/Stop action uses Apple's `AVSpeechSynthesizer` and the installed
system voice. iOS selects a playback/spoken-audio session, so an explicit playback
action is not dependent on the ringer setting; it releases the session afterward.
No audio is uploaded and no Bedrock/Polly request is made. Leaving the detail view,
withdrawal/expiry while visible, or Stop cancels speech. Voice availability, volume
and audible physical-device output still require the user's check.
[Apple speech-synthesis documentation](https://developer.apple.com/documentation/avfoundation/speech-synthesis).

## Shelter details and required location

`PUT /v1/shelters/{id}/details` requires dispatcher authorization for that shelter
and an expected revision. A lost-response retry with identical content is safe.
The paired optional coordinates are bounded/finite; address <=240 characters and
instructions <=1,500. Directory responses include these details alongside the
unchanged enrolled receiver/key address. No receiving identity is overwritten.

Settings → shelter information → Edit lets staff publish an address, coordinates
and confirmed arrival instructions. “Use this device's location” is explicit and
should only be used at the shelter. The resident can open the same cached
information from the Help form or an announcement. Haversine distance is labelled
straight-line distance, includes snapshot time/accuracy, and is not a road route,
safe access assessment, travel time or availability promise. The Maps link opens
the shelter coordinate; Maps may need internet. No AI invents directions.

The current native Help composer requires either a validated location snapshot
or a nonblank typed address, landmark, entrance or room. A resident can decline
GPS permission and type a location. Review shows exactly what will be sent.
This requirement is intentionally applied at new native submission/review, not
by mutating or rejecting previously persisted wire payloads. Older API clients
can still submit the previous location-optional schema; the server has not been
advertised as enforcing a new location-required protocol version.

## Accounts versus device IDs

| Identifier | Purpose |
|---|---|
| Cognito `sub` | Stable account identity verified from the access token |
| Configured membership | Requester/dispatcher role, incident and authorized shelters |
| Local persistent UUID | Device identity and nearby routing, survives app upgrade |
| Device signing/encryption keys | Signed/encrypted nearby request and receipt protocol |
| Request UUID | Immutable logical request shared by HTTP and nearby delivery |
| Announcement UUID | One publication, reused on retry |

The same account on two phones is still the same account, despite different
device UUIDs. A carrier does not become the sender or gain their account access.
People currently receive credentials from the organizer through a private
channel and sign in online once before the offline exercise. This demo uses
pre-enrolled synthetic Cognito accounts, including separate RequesterA and
RequesterB on the two owned phones. MFA enrollment and backend membership must
also exist. Public sign-up, invitation redemption, password recovery UI and a
staff enrollment console are not implemented. Do not share a dispatcher login
with residents or include credential files in the repository.

## Reproduce

1. Update both original phone apps and Mac to build20. Keep internet available and
   each account signed in. Mac is the coordinator, phones use separate residents.
2. Mac → Alerts → New announcement. Prefix it `DEMO ONLY`, set an expiry, review
   and publish. Both phones → Alerts → Refresh. Compare the same title/body.
3. Open on one phone: NEW clears there; Listen/Stop works independently of ASR.
   Withdraw on Mac; refresh phones; notice moves to Expired & withdrawn.
4. Download another notice, pause cloud in Settings → Demo tools, restart the app,
   and verify the cache/read state. A new Mac notice cannot reach the paused phone
   until cloud resumes. This software isolation does not prove radio independence.
5. Mac → Settings → Shelter A information → Edit. Publish synthetic clearly labelled
   test coordinates/instructions. Resident → Help → Shelter location & arrival
   instructions → Use my location for distance. Verify the label and timestamp.
   Replace/clear synthetic coordinates afterward; do not use them for real travel.
6. New Help request: leave snapshot and landmark empty. Review must show a location
   error and disable Send. Type a landmark instead; sending becomes available.

Automated: `swift test`, `python -m pytest cloud/tests -q`. Explicit live synthetic
API test: `PYTHONPATH=cloud python cloud/scripts/announcement_smoke.py --config
<private-config> --sessions <private-demo-enrollment-directory> --output
/tmp/relay-announcement-check.json`. It creates then withdraws one test notice,
checks both owned resident accounts and verifies forbidden resident publication.
It prints no credentials and performs no AI calls. Evidence is in
`docs/evidence/build20` and `TEST_RESULTS.md`.
