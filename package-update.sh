#!/bin/bash
# Builds a signed archive and signed GitHub Releases feed without publishing.
# Usage: ./package-update.sh X.Y.Z
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Usage: ./package-update.sh X.Y.Z' >&2; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo 'Commit the finished source before packaging a release.' >&2; exit 1; }
[[ "$(git rev-parse "v$VERSION^{commit}")" == "$(git rev-parse HEAD)" ]] || { echo 'The release tag must point at the current commit.' >&2; exit 1; }
SMARTERSHOT_VERSION="$VERSION" ./make-app.sh
TOOLS="$PWD/.build/artifacts/sparkle/Sparkle/bin"
PUBLIC_KEY="$("$TOOLS/generate_keys" --account app.smartershot.SmarterShot -p)"
[[ "$PUBLIC_KEY" == "$(cat update-public-key.txt)" ]] || { echo 'Update signing key does not match the app.' >&2; exit 1; }
OUT="$PWD/dist/update-v$VERSION"
[[ ! -e "$OUT" ]] || { echo "Already exists: $OUT. Choose a new version or move the previous package aside." >&2; exit 1; }
mkdir -p "$OUT"
ARCHIVE="SmarterShot-v$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent dist/SmarterShot.app "$OUT/$ARCHIVE"
# Embedded plain release notes avoid third-party HTML or tracking resources.
python3 - "$VERSION" "$OUT/${ARCHIVE%.zip}.txt" <<'PY'
from pathlib import Path
import sys
version, output = sys.argv[1:]
text = Path('CHANGELOG.md').read_text()
marker = f'## [{version}]'
if marker not in text:
    marker = '## [Unreleased]'
notes = text.split(marker, 1)[1].split('\n## [', 1)[0].strip()
# Remove the dated heading tail when packaging a tagged changelog entry.
if notes.startswith('- '): notes = notes.split('\n', 1)[-1].strip()
Path(output).write_text(notes or f'SmarterShot {version}')
PY
"$TOOLS/generate_appcast" --account app.smartershot.SmarterShot \
    --download-url-prefix "https://github.com/SmarterTec/SmarterShot/releases/download/v$VERSION/" \
    --link 'https://github.com/SmarterTec/SmarterShot' \
    --maximum-deltas 0 --embed-release-notes "$OUT"
"$TOOLS/sign_update" --account app.smartershot.SmarterShot --verify "$OUT/appcast.xml"
echo "Prepared $OUT. Nothing has been published."
