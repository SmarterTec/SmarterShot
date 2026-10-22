#!/bin/bash
# Cuts a new release: moves the CHANGELOG [Unreleased] notes under the new
# version, commits, and tags vX.Y.Z. Build/sign locally before publishing.
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
echo "Next, prepare and verify the signed update locally:"
echo "    ./package-update.sh $VERSION"
echo "    ./test-updates.sh dist/update-$TAG"
echo "After reviewing the release, push the source/tag and publish signed assets:"
echo "    git push origin HEAD $TAG"
echo "    ./publish-update.sh $VERSION"
