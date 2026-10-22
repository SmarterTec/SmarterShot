#!/bin/bash
# Assembles SmarterShot.app and signs it with the pinned, persistent identity.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/dist/SmarterShot.app"
BIN="$ROOT/.build/release/SmarterShot"

# Check before rebuilding or replacing any bundle. Missing/locked identities
# must never silently produce an ad-hoc-signed update with a new privacy identity.
SIGN_ID="${SMARTERSHOT_SIGN_ID-$(cat "$ROOT/signing-identity.sha1")}"
SIGN_KC="${SMARTERSHOT_SIGN_KC:-$HOME/Library/Keychains/login.keychain-db}"
if [[ ! "$SIGN_ID" =~ ^[[:xdigit:]]{40}$ ]]; then
    echo "Signing requires the exact 40-character certificate fingerprint; ad-hoc signing is disabled." >&2
    exit 1
fi
if ! security find-identity -v -p codesigning "$SIGN_KC" | grep -Fqi "$SIGN_ID"; then
    echo "Pinned signing identity $SIGN_ID is unavailable in $SIGN_KC." >&2
    echo "Unlock the login keychain or restore the existing identity from its encrypted backup. Do not generate a replacement certificate." >&2
    exit 1
fi

echo "Building release binary..."
swift build -c release >/dev/null

echo "Assembling app bundle..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/SmarterShot"

# Preserve framework symlinks. Non-sandboxed apps do not need Sparkle's XPC
# services; the framework's installer and relaunch helper remain embedded.
SPARKLE_SRC="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SPARKLE_SRC" "$SPARKLE"
rm -rf "$SPARKLE/Versions/B/XPCServices" "$SPARKLE/XPCServices"
for helper in "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app"; do
    codesign --force --sign "$SIGN_ID" --keychain "$SIGN_KC" --options runtime "$helper"
done
codesign --force --sign "$SIGN_ID" --keychain "$SIGN_KC" "$SPARKLE"

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
    <key>SUFeedURL</key><string>https://github.com/SmarterTec/SmarterShot/releases/latest/download/appcast.xml</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUAutomaticallyUpdate</key><false/>
    <key>SUAllowsAutomaticUpdates</key><false/>
    <key>SUEnableSystemProfiling</key><false/>
    <key>SUVerifyUpdateBeforeExtraction</key><true/>
    <key>SURequireSignedFeed</key><true/>
    <key>SUSignedFeedFailureExpirationInterval</key><integer>0</integer>
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
VERSION="${SMARTERSHOT_VERSION:-$VERSION}"
BUILD="${SMARTERSHOT_BUILD:-$(git -C "$ROOT" rev-list --count HEAD 2>/dev/null || echo 1)}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $(cat "$ROOT/update-public-key.txt")" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :SmarterShotSourceRevision string $(git -C "$ROOT" rev-parse HEAD)" "$APP/Contents/Info.plist"
echo "Version $VERSION (build $BUILD)."

# A fixed certificate and designated requirement let macOS recognize updates
# even when the executable changes. Never fall back to an ad-hoc signature.
echo "Code signing with pinned certificate $SIGN_ID..."
codesign --force --sign "$SIGN_ID" --keychain "$SIGN_KC" \
    --identifier app.smartershot.SmarterShot \
    --requirements "=designated => identifier \"app.smartershot.SmarterShot\" and certificate leaf = H\"$SIGN_ID\"" \
    "$APP"
codesign --verify --deep --strict "$APP"
echo "Done: $APP"
