#!/usr/bin/env bash
# Renders Assets/AppIcon.svg to the Mac icon (Assets/AppIcon.icns) and the iPhone icon, with
# headless Chrome, sips, and iconutil.
set -euo pipefail
cd "$(dirname "$0")/.."
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
work="$(mktemp -d)"
"$chrome" --headless=new --disable-gpu --hide-scrollbars --default-background-color=00000000 \
    --window-size=1024,1024 --screenshot="$work/icon_1024.png" "file://$PWD/Assets/AppIcon.svg" 2>/dev/null
set="$work/AppIcon.iconset"
mkdir -p "$set"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$work/icon_1024.png" --out "$set/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) "$work/icon_1024.png" --out "$set/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$set" -o Assets/AppIcon.icns
cp "$work/icon_1024.png" Assets/AppIcon.png
echo "wrote Assets/AppIcon.icns"

# iOS rounds the corners itself and wants the art to fill the square, so the iPhone icon is the
# Mac icon's body alone: the view cropped to it and its corners squared.
sed -e 's/viewBox="0 0 1024 1024"/viewBox="100 100 824 824"/' -e 's/ rx="185"//' \
    Assets/AppIcon.svg >"$work/phone.svg"
phone=Apps/iOS/HablamonPhone/Assets.xcassets/AppIcon.appiconset/AppIcon.png
"$chrome" --headless=new --disable-gpu --hide-scrollbars --default-background-color=121836ff \
    --window-size=1024,1024 --screenshot="$work/phone.png" "file://$work/phone.svg" 2>/dev/null
cp "$work/phone.png" "$phone"
echo "wrote $phone"
