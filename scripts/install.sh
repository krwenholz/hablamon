#!/usr/bin/env bash
# Builds Hablamon.app in release mode, signs it ad hoc, installs it to ~/Applications, and links
# the CLI into ~/.local/bin. Data lives in ~/Library/Application Support/Hablamon and is never touched,
# so reinstalling keeps settings, characters, known words, transcripts, and logs.
set -euo pipefail

cd "$(dirname "$0")/.."
bundle_id="dev.krw.hablamon"
app="$HOME/Applications/Hablamon.app"
staging="$(mktemp -d)/Hablamon.app"

# MLX's shaders need Xcode's Metal Toolchain, a separate download per Xcode version. Swift Build
# compiles them during `swift build`, so fetch it first (again after an Xcode update).
if ! xcrun metal -v >/dev/null 2>&1; then
    echo "Downloading Xcode's Metal Toolchain (one time per Xcode version, ~700 MB)…"
    xcodebuild -downloadComponent MetalToolchain
fi
swift build -c release
bin="$(swift build -c release --show-bin-path)"
scripts/build-metallib.sh release

mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources"
cp "$bin/HablamonApp" "$staging/Contents/MacOS/Hablamon"

# SwiftPM resource bundles (glossary, character table, game profiles); Bundle.module finds them here.
cp -R "$bin"/*.bundle "$staging/Contents/Resources/"
# MLX's Metal shaders for the voices; MLX finds them as default.metallib in its own resource bundle.
mkdir -p "$staging/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources"
cp -L "$bin/mlx.metallib" "$staging/Contents/Resources/mlx-swift_Cmlx.bundle/Contents/Resources/default.metallib"
cp Assets/AppIcon.icns "$staging/Contents/Resources/AppIcon.icns"

version="$(git describe --always --dirty 2>/dev/null || echo dev)"
cat >"$staging/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>$bundle_id</string>
    <key>CFBundleName</key><string>Hablamon</string>
    <key>CFBundleDisplayName</key><string>Hablamon</string>
    <key>CFBundleExecutable</key><string>Hablamon</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>$version</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.education</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSCameraUsageDescription</key><string>Hablamon reads the game's dialogue boxes through your iPhone camera.</string>
    <key>NSCameraUseContinuityCameraDeviceType</key><true/>
</dict>
</plist>
PLIST

# Ad hoc signature with a stable identifier, so macOS keeps the camera permission across rebuilds.
codesign --force --sign - --identifier "$bundle_id" "$staging"

mkdir -p "$HOME/Applications" "$HOME/.local/bin"
rm -rf "$app"
mv "$staging" "$app"
ln -sf "$bin/hablamon" "$HOME/.local/bin/hablamon"

echo "installed $app ($version)"
echo "linked ~/.local/bin/hablamon"
echo "try: open \"$app\" --args --replay \"$PWD/Tests/Fixtures/videos/academy-lobby_far.mp4\""
