#!/usr/bin/env bash
# Builds the iPhone app and runs it in the iOS Simulator, with a fixture video standing in for the
# camera. Usage: scripts/phone-sim.sh [video]
#
# This covers OCR, Kokoro (on the CPU), and the screen. The simulator has no camera or translation,
# so PhoneCamera, calibration, and the English line still need a real phone (mise run phone).
set -euo pipefail

cd "$(dirname "$0")/.."
video="${1:-Tests/Fixtures/videos/far.mp4}"
device="iPhone 17 Pro"
derived=.build/ios-sim

if [ ! -f "$video" ]; then
    echo "No video at $video. Run mise run fixtures, or pass a path." >&2
    exit 1
fi
video="$(realpath "$video")"

mkdir -p "$derived"
log="$derived/build.log"
status=0
xcodebuild -project Apps/iOS/Hablamon.xcodeproj -scheme HablamonPhone -configuration Release \
    -destination "platform=iOS Simulator,name=$device" -derivedDataPath "$derived" \
    -skipMacroValidation -skipPackagePluginValidation CODE_SIGNING_ALLOWED=NO \
    build >"$log" 2>&1 || status=$?
grep -E 'error:|^\*\*' "$log" | sort -u || true
if [ "$status" -ne 0 ]; then
    echo "Build failed; the full log is $log." >&2
    exit 1
fi

xcrun simctl bootstatus "$device" -b >/dev/null
open -a Simulator
xcrun simctl install "$device" "$derived/Build/Products/Release-iphonesimulator/Hablamon.app"
xcrun simctl launch --terminate-running-process "$device" dev.krw.hablamon.phone --replay "$video"
