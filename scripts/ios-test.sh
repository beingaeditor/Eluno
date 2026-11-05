#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Eluno iOS tests require macOS with full Xcode selected." >&2
  exit 1
fi

# Any available iPhone simulator works, because these tests don't launch the app.
simulator=$(xcrun simctl list --json devices available | node -e '
  const { devices } = JSON.parse(require("node:fs").readFileSync(0, "utf8"));
  const phone = Object.values(devices).flat().find(device => device.name.startsWith("iPhone"));
  if (!phone) { console.error("No available iPhone simulator."); process.exit(1); }
  console.log(phone.udid);
')

xcodebuild -project apps/ios/Eluno.xcodeproj -scheme Eluno -configuration Debug \
  -destination "platform=iOS Simulator,id=$simulator" \
  -derivedDataPath release/apple/tests CODE_SIGNING_ALLOWED=NO test
