#!/bin/bash
# Archive, optionally upload, using the enrolled account already signed into Xcode.
# Never pass passwords, private keys, or API tokens to this script.
set -euo pipefail
if [[ $# -lt 1 || $# -gt 2 || ! "$1" =~ ^[1-9][0-9]*$ ]]; then
  echo "Usage: RELAY_TEAM_ID=... RELAY_BUNDLE_ID=... bash scripts/testflight.sh BUILD_NUMBER [--upload]" >&2
  exit 2
fi
relay_build_number="$1"
relay_mode="${2:-archive}"
if [[ "$relay_mode" != archive && "$relay_mode" != --upload ]]; then
  echo "The only optional argument is --upload." >&2
  exit 2
fi
: "${RELAY_TEAM_ID:?Set the enrolled Developer Program team ID}"
: "${RELAY_BUNDLE_ID:?Set the bundle ID registered to that team and App Store Connect app}"
relay_root="$(cd "$(dirname "$0")/.." && pwd)"
relay_output="$(mktemp -d /tmp/RELAY-testflight.XXXXXX)"
echo "Build artifacts and logs: $relay_output"
xcodebuild -project "$relay_root/RELAY.xcodeproj" -scheme RELAY-iOS \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$relay_output/DerivedData" \
  -archivePath "$relay_output/RELAY.xcarchive" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$RELAY_TEAM_ID" PRODUCT_BUNDLE_IDENTIFIER="$RELAY_BUNDLE_ID" \
  CURRENT_PROJECT_VERSION="$relay_build_number" archive 2>&1 | tee "$relay_output/archive.log"
if [[ "$relay_mode" == --upload ]]; then
  python3 - "$relay_output/ExportOptions.plist" "$RELAY_TEAM_ID" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(method='app-store-connect', destination='upload',
                      signingStyle='automatic', teamID=sys.argv[2],
                      manageAppVersionAndBuildNumber=False,
                      uploadSymbols=True, testFlightInternalTestingOnly=False), f)
PY
  xcodebuild -exportArchive -archivePath "$relay_output/RELAY.xcarchive" \
    -exportPath "$relay_output/Export" -exportOptionsPlist "$relay_output/ExportOptions.plist" \
    -allowProvisioningUpdates 2>&1 | tee "$relay_output/upload.log"
  echo "Check App Store Connect processing and beta review status before sharing with testers."
else
  echo "Archive created. Nothing uploaded. Add --upload for an explicitly requested TestFlight release."
fi
