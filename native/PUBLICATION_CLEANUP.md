# Public repository cleanup —24October2026

This is the complete native prototype source snapshot from `5a2df96ca7eca4cc4a806da29cc613a149cfaa56`,
imported under `native/` on the team's `dev` branch. It includes the Apple app,
Swift engine/tests, Python backend/tests, infrastructure examples and synthetic
fixtures. The existing React/Expo/web/API work is preserved at the repository root.
The two backend stacks have distinct contracts; this import does not claim they
are integrated.

## Included and excluded

- All 122 checked application/core/backend/test/script/config/fixture files
  are byte-for-byte identical to the tested source snapshot, plus Package.swift.
- No private repository commit history was imported. The team's existing public
  history remains the parent of the new commit; there is no force-push or deletion.
- Private accounts, passwords, access/refresh tokens, MFA seeds, AWS credential
  files, session files, databases, recorded user audio, signing keys/profiles,
  archives and IPAs are absent. Private runtime state remains outside this repo.
- Personal emails, developer home paths, device labels and identifiers in historical
  documentation/evidence are redacted. `REDACTED-ID-*` is a stable redaction label,
  not an actual test message ID. Historical source hashes still describe source
  files; altered public evidence transcripts should not be compared byte-for-byte
  against the original private records.
- Seven historical simulator screenshots are omitted to avoid publishing device
  identifiers. App icon assets and the explicitly synthetic speech fixture remain.
- Existing public API URLs, Cognito pool/public-client IDs, AWS resource names and
  Apple bundle/team IDs are configuration identifiers, not authentication secrets.
  Using an account still requires authentication and authorized membership. New
  deployments should use their own AWS resources and Apple signing team.
- Ignore rules now cover private JSON/session files, local databases, signing
  material and generated native/Python outputs.

## Verification

- Gitleaks8.30.1 scanned the source history, destination history and final public
  working tree. The only initial findings were10 SHA-256 source checksums and one
  literal browser localStorage key. Each was checked against its exact source line.
  `.gitleaks.toml` contains narrowly matched exceptions for those values/formats;
  all default credential detectors remain enabled. Final scan: **zero findings**.
- Compared the exported files against34 locally stored credential/token/MFA values
  without logging their contents: **zero matches**. This is an additional check,
  not a guarantee that any scanner detects every possible secret format.
- Relocated native Swift tests: **84 passed**, zero failures.
- Relocated Python backend tests: **111 passed**, one existing dependency warning.
- Relocated iOS Simulator Xcode build: **PASS** (arm64, code signing disabled).
- Existing team implementation files and package locks are unchanged. Only the
  root README/ignore rules and scan configuration accompany the new native folder.
- Physical radio acceptance and TestFlight release availability are unchanged by
  this repository publication; see TEST_RESULTS.md.

## Repeat the scan

From the repository root, with Gitleaks installed:

```sh
gitleaks dir --config .gitleaks.toml --redact=100 .
gitleaks git --config .gitleaks.toml --redact=100 .
```

Do not commit a report that contains unredacted secret matches. Configure actual
credentials locally using the documented SDK/provider credential chain.
