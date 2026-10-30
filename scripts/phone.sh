#!/usr/bin/env bash
# Builds the iPhone app (Release) and installs and launches it on a connected iPhone: by cable, or
# over Wi-Fi once Xcode has paired with the phone. Usage: scripts/phone.sh [device name or UDID]
#
# Signing uses the team in Apps/iOS/Local.xcconfig. The first time, this script finds the team in
# the Apple Development certificate Xcode created for your Apple ID and writes that file.
set -euo pipefail

cd "$(dirname "$0")/.."
project=Apps/iOS/Hablamon.xcodeproj
local_config=Apps/iOS/Local.xcconfig
bundle_id=dev.krw.hablamon.phone
derived=.build/ios

if [ ! -f "$local_config" ]; then
    # The team ID is the certificate's organizational unit (OU).
    team="$(security find-certificate -c "Apple Development" -p 2>/dev/null |
        openssl x509 -noout -subject 2>/dev/null |
        sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -n 1 || true)"
    if [ -z "$team" ]; then
        cat >&2 <<'EOF'
No Apple Development certificate found, so the signing team is unknown. Once:
  1. Xcode › Settings › Accounts: add your Apple ID.
  2. Open Apps/iOS/Hablamon.xcodeproj, select the HablamonPhone target › Signing & Capabilities,
     pick your (Personal) Team, choose your iPhone, and press Run.
Then run this again. Or write Apps/iOS/Local.xcconfig yourself with: DEVELOPMENT_TEAM = <team ID>
EOF
        exit 1
    fi
    printf '// Written by scripts/phone.sh; not in git.\nDEVELOPMENT_TEAM = %s\n' "$team" >"$local_config"
    echo "Signing with team $team ($local_config)"
fi
if grep -q '^PRODUCT_BUNDLE_IDENTIFIER' "$local_config"; then
    bundle_id="$(sed -n 's/^PRODUCT_BUNDLE_IDENTIFIER *= *//p' "$local_config" | head -n 1)"
fi

# Find the phone: the one named on the command line, or the first paired iPhone.
devices_json="$(mktemp)"
trap 'rm -f "$devices_json"' EXIT
xcrun devicectl list devices --json-output "$devices_json" >/dev/null
read -r device udid name < <(python3 -I - "$devices_json" "${1:-}" <<'EOF'
import json, sys

devices = json.load(open(sys.argv[1]))["result"]["devices"]
wanted = sys.argv[2]
phones = []
for d in devices:
    hardware, connection = d.get("hardwareProperties", {}), d.get("connectionProperties", {})
    if hardware.get("platform") != "iOS" or connection.get("pairingState") != "paired":
        continue
    name = d.get("deviceProperties", {}).get("name", "?")
    udid = hardware.get("udid", "")
    if wanted and wanted not in (name, udid, d["identifier"]):
        continue
    connected = connection.get("tunnelState") == "connected"
    phones.append((not connected, d["identifier"], udid, name))
if not phones:
    sys.exit("No paired iPhone found. Plug it in, unlock it, and trust this Mac.")
_, identifier, udid, name = sorted(phones)[0]
print(identifier, udid, name.replace(" ", " "))
EOF
)
[ -n "${device:-}" ] || exit 1
echo "Building for $name…"

# Naming the device lets automatic signing register it with a free team.
mkdir -p "$derived"
log="$derived/build.log"
status=0
xcodebuild -project "$project" -scheme HablamonPhone -configuration Release \
    -destination "id=$udid" -derivedDataPath "$derived" \
    -allowProvisioningUpdates -skipMacroValidation -skipPackagePluginValidation \
    build >"$log" 2>&1 || status=$?
grep -E 'error:|^\*\*' "$log" | sort -u || true
if [ "$status" -ne 0 ]; then
    echo "Build failed; the full log is $log (or open $project in Xcode)." >&2
    exit 1
fi
app="$derived/Build/Products/Release-iphoneos/Hablamon.app"

xcrun devicectl device install app --device "$device" "$app"
xcrun devicectl device process launch --device "$device" "$bundle_id" ||
    echo "Installed. If it won't open, trust the developer on the phone: Settings › General › VPN & Device Management."
