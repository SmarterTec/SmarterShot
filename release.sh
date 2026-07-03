#!/bin/bash
# Cuts a new release: moves the CHANGELOG [Unreleased] notes under the new
# version, commits, tags vX.Y.Z, and (if you push the tag) the GitHub Action
# builds the app and publishes a Release.
#
# Usage:  ./release.sh 1.1.0
set -euo pipefail

VERSION="${1:-}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: ./release.sh X.Y.Z   (e.g. ./release.sh 1.1.0)"
    exit 1
fi
TAG="v$VERSION"
ROOT="$(cd "$(dirname "$0")" && pwd)"
DATE="$(date +%Y-%m-%d)"

if git -C "$ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
    echo "Tag $TAG already exists."; exit 1
fi

# Rename the [Unreleased] heading to the new version + date, add a fresh one.
python3 - "$ROOT/CHANGELOG.md" "$VERSION" "$DATE" <<'PY'
import sys
path, version, date = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(path).read()
marker = "## [Unreleased]"
if marker not in text:
    raise SystemExit("No [Unreleased] section in CHANGELOG.md")
text = text.replace(marker, f"## [Unreleased]\n\n## [{version}] - {date}", 1)
open(path, "w").write(text)
PY

git -C "$ROOT" add CHANGELOG.md
git -C "$ROOT" commit -m "Release $TAG" >/dev/null
git -C "$ROOT" tag -a "$TAG" -m "SmarterShot $TAG"

echo "Committed and tagged $TAG."
echo "To publish (builds + creates the GitHub Release):"
echo "    git push origin main $TAG"
