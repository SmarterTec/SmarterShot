#!/bin/bash
# Assembles SmarterShot.app from the compiled binary, ad-hoc signs it.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/SmarterShot.app"
BIN="$ROOT/.build/release/SmarterShot"

echo "Building release binary..."
swift build -c release >/dev/null

echo "Assembling app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SmarterShot"

# App icon. Override which variant is used with SMARTERSHOT_ICON=dark.
ICON_VARIANT="${SMARTERSHOT_ICON:-light}"
ICON_SRC="$ROOT/icon/SmarterShot.icns"
[ "$ICON_VARIANT" = "dark" ] && ICON_SRC="$ROOT/icon/SmarterShot-dark.icns"
if [ -f "$ICON_SRC" ]; then
    cp "$ICON_SRC" "$APP/Contents/Resources/SmarterShot.icns"
    echo "Using $ICON_VARIANT app icon."
fi

# Capture sounds.
if [ -d "$ROOT/sounds/bundled" ]; then
    mkdir -p "$APP/Contents/Resources/Sounds"
    cp "$ROOT"/sounds/bundled/*.wav "$APP/Contents/Resources/Sounds/"
    echo "Bundled capture sounds."
fi

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>SmarterShot</string>
    <key>CFBundleDisplayName</key>       <string>SmarterShot</string>
    <key>CFBundleIdentifier</key>        <string>app.smartershot.SmarterShot</string>
    <key>CFBundleExecutable</key>        <string>SmarterShot</string>
    <key>CFBundleIconFile</key>          <string>SmarterShot</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>CFBundleVersion</key>           <string>1</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>LSUIElement</key>               <true/>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSHumanReadableCopyright</key>  <string>Released under the MIT License.</string>
</dict>
</plist>
PLIST

# Version: semantic version from the latest git tag (vX.Y.Z), build number from
# the commit count — so every commit bumps the build automatically.
VERSION="$(git -C "$ROOT" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
[ -z "$VERSION" ] && VERSION="1.0.0"
BUILD="$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
echo "Version $VERSION (build $BUILD)."

# Signing.
#
# By default the app is ad-hoc signed, which works for local personal use.
#
# Optionally, sign with a stable local self-signed identity so macOS remembers
# the Screen Recording permission across rebuilds. To use it, set these env vars:
#   SMARTERSHOT_SIGN_ID   name of a code-signing identity in the keychain below
#   SMARTERSHOT_SIGN_KC   path to that keychain (default: smartershot-signing)
#   SMARTERSHOT_SIGN_PW   password to unlock that keychain
# No credentials are hard-coded here.
SIGN_ID="${SMARTERSHOT_SIGN_ID:-}"
SIGN_KC="${SMARTERSHOT_SIGN_KC:-$HOME/Library/Keychains/smartershot-signing.keychain-db}"
SIGN_PW="${SMARTERSHOT_SIGN_PW:-}"

if [ -n "$SIGN_ID" ] && [ -f "$SIGN_KC" ] \
   && security find-identity -p codesigning "$SIGN_KC" | grep -q "$SIGN_ID"; then
    echo "Code signing with '$SIGN_ID'..."
    [ -n "$SIGN_PW" ] && security unlock-keychain -p "$SIGN_PW" "$SIGN_KC"
    codesign --force --deep --sign "$SIGN_ID" --keychain "$SIGN_KC" "$APP"
else
    echo "Ad-hoc code signing..."
    codesign --force --deep --sign - "$APP"
fi

echo "Done: $APP"
