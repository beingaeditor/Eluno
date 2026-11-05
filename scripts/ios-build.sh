#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."
if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "Eluno iOS builds require macOS with full Xcode selected." >&2
  exit 1
fi

xcodebuild -version
plutil -lint -- \
  apps/ios/Eluno/Info.plist apps/ios/Eluno/Eluno.entitlements \
  apps/ios/Eluno/PrivacyInfo.xcprivacy \
  apps/ios/ShareExtension/Info.plist apps/ios/ShareExtension/Share.entitlements

project=apps/ios/Eluno.xcodeproj

xcodebuild -project "$project" -scheme Eluno -configuration Debug \
  -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath release/apple/simulator CODE_SIGNING_ALLOWED=NO build

xcodebuild -project "$project" -scheme Eluno -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath release/apple/device CODE_SIGNING_ALLOWED=NO build

for app in release/apple/simulator/Build/Products/Debug-iphonesimulator/Eluno.app \
           release/apple/device/Build/Products/Release-iphoneos/Eluno.app; do
  if [[ ! -f "$app/PrivacyInfo.xcprivacy" || ! -f "$app/PlugIns/ElunoShare.appex/Info.plist" ]]; then
    echo "Eluno build is missing its privacy manifest or Share Extension in $app" >&2
    exit 1
  fi
done
