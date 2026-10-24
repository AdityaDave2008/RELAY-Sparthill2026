# RELAY development notes

Read README.md, TEST_RESULTS.md, and TEST_PLAN.md before changing the prototype.
This directory contains the RELAY Apple app and shared relay engine. The surrounding
repository also contains the team's React/Expo applications and a separate API. Keep
changes scoped to the requested stack and preserve the other team applications.

- Keep implemented features distinct from the proposed product scope in README.md.
- Never infer physical offline or router-independent success from unit tests,
  simulators, loopback tests, path opt-in flags, or successful builds.
- Preserve existing SQLite identities, immutable message IDs, messages, and
  receipt state across upgrades. Add migration tests for schema changes.
- A relay storage ACK, final recipient receipt, cloud acceptance, dispatcher
  assignment, and resource fulfillment are separate states.
- Names are labels. Future shelter/team inbox IDs and authenticated membership
  must be separate from device UUIDs and the A/B/C lab roles.
- Never commit credentials, signing keys/profiles, databases, or build products.
  Use synthetic data in test fixtures and evidence.
- Run `swift test` for core changes and the affected Xcode target build for UI
  changes. For transport/store changes also run `python3 scripts/tcp_experiment.py`.
- Use temporary DerivedData/archive directories outside the source checkout.
- Record actual validation and limitations in TEST_RESULTS.md. Cloud integration,
  Android transport, encryption, and organizational identity are not implemented
  merely because they appear in the roadmap.
- Do not claim deployment, TestFlight approval, phone installation, or cloud
  processing without evidence from the corresponding system.
