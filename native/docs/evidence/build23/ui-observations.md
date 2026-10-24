# Build23 setup replay,24October2026

- Native Simulator update/launch with --relay-replay-resident-setup visibly showed
  WELCOME TO RELAY / A little about you / Save and continue / Skip for now. Existing
  synthetic name/language/photo and optional fields were retained.
- Skip for now advanced to guide1of6. Skip tour completed it. Terminate/relaunch
  without the argument opened Ask for help, confirming normal launches do not replay.
- Original15ProMax installed23 and launched. Initial replay readback still showed
  completed flags; this was not counted as success. Restored the same prepared demo
  session and launched with the direct argument (no literal separator). Final
  readback showed both flagsfalse for the correct account; other account state
  remainedtrue. Session import consumed. No physical screen capture was made.
- Phone53messages and all prior bodies/receipts/cloud submissions/deviceID/keys
  remained. SQLite quick_checkok. Profile Keychain values were not modified/read.
- DEBUG-only helper, no public workflow/schema/transport change. No new AWS calls
  beyond normal foreground polling, no inventory mutation, no new radio test.
- All three native targets compiled; only15ProMax and Simulator installed23.
  Mac/16remain22. No23TestFlight upload. Previous84Swift/111backend suite remains
  the latest unit run; unchanged core/backend were not rerun for this UI launch hook.
