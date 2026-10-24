# Mobile testing — build22

New in22: [profile photo, selected sharing, cleaner Help and dedicated login](docs/RESIDENT_SETUP.md).
Both original phone apps installed and launched22. Open Settings → Photo & personal
details, choose a picture, enter a display name and preferred language, then Save.
Health fields remain optional. In a new request's review, choose whether to attach
basic/health/support details. The Mac's request detail shows selected text; photo
stays local. The question-mark icon beside Ask for help reopens the guide.

New in20: [alerts, shelter instructions/distance and location checks](cloud/docs/ANNOUNCEMENTS.md#reproduce).
Each resident needs a separate organizer-issued account; public self-registration
is not implemented. Both owned phones already have separate resident test accounts.

Use [MORNING_DEMO.md](MORNING_DEMO.md) as the current procedure: two requester
iPhones and the native Mac as Shelter A. It covers live speech, transcript review,
Bedrock fields, required location snapshot OR typed landmark, sending, coordinator reservation/handover,
nearby delivery, carrier restart and the returning signed receipt.

The older build15 setup with one requester phone and one coordinator phone is
superseded. Nearby devices are transport participants; users select the shelter.
No shelter code is needed for the authenticated main workflow once its directory
and receiver keys are cached online. Legacy shelter-code tools remain in Settings.

The current API is https://relay.stepcheck.app. This Mac still hosts its API/worker.
Keep it awake and online for AWS services. Before presenting, run the read-only
[hosting preflight](cloud/docs/DEMO_HOSTING.md); health alone cannot detect expired
AWS credentials. Accounts are organizer-provided synthetic RELAY accounts, separate
from Apple or AWS-console sign-in. Never put passwords or enrollment files in Git.

Both original physical phone apps were updated to build22 and launched. Physical
mic/GPS/radio checks remain operator steps. Update the same
bundle in place to preserve identity and SQLite data. The paid/TestFlight and original
USB bundles have separate stores. See [TESTFLIGHT.md](TESTFLIGHT.md) for release status.

For actual no-internet/no-router claims, execute [TEST_PLAN.md](TEST_PLAN.md) A–E.
Keep Wi-Fi radios on, foreground apps awake, and record the network conditions on
every participant. Simulator checks and the software cloud-pause toggle are not
physical wireless evidence. Use synthetic data only.
