#!/bin/bash
# Reopen first-run setup in the owned development app; no profile/history deletion.
set -euo pipefail
if [[ $# -ne 1 ]]; then
  echo "Usage: bash scripts/replay_resident_setup.sh CORE_DEVICE_ID" >&2
  exit 2
fi
xcrun devicectl device process launch --device "$1" --terminate-existing \
  --timeout 25 org.relay.prototype.ios --relay-replay-resident-setup
