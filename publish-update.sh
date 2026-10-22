#!/bin/bash
# Publish a package already prepared by package-update.sh. No private key is
# uploaded: only the signed app archive and signed public appcast are released.
set -euo pipefail
cd "$(dirname "$0")"
VERSION="${1:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Usage: ./publish-update.sh X.Y.Z' >&2; exit 1; }
TAG="v$VERSION"
OUT="$PWD/dist/update-$TAG"
./test-updates.sh "$OUT"
git rev-parse "$TAG" >/dev/null
# Ensure the remote tag is the reviewed source used to create this package.
LOCAL="$(git rev-parse "$TAG^{commit}")"
python3 - "$OUT/SmarterShot-$TAG.zip" "$LOCAL" "$TAG" <<'PYCODE'
import plistlib,sys,zipfile
with zipfile.ZipFile(sys.argv[1]) as z:
    p=plistlib.loads(z.read('SmarterShot.app/Contents/Info.plist'))
assert p['SmarterShotSourceRevision']==sys.argv[2], 'Package does not match the release tag.'
assert 'v'+p['CFBundleShortVersionString']==sys.argv[3], 'Package version does not match the release tag.'
PYCODE
REMOTE="$(git ls-remote origin "refs/tags/$TAG^{}" | cut -f1)"
[[ -n "$REMOTE" ]] || REMOTE="$(git ls-remote origin "refs/tags/$TAG" | cut -f1)"
[[ "$LOCAL" == "$REMOTE" ]] || { echo 'Push the matching release tag before publishing.' >&2; exit 1; }
if gh release view "$TAG" --repo SmarterTec/SmarterShot >/dev/null 2>&1; then
    [[ "$(gh release view "$TAG" --repo SmarterTec/SmarterShot --json isDraft --jq .isDraft)" == true ]] || { echo 'Refusing to replace an already published release.' >&2; exit 1; }
else
    gh release create "$TAG" --repo SmarterTec/SmarterShot --verify-tag --draft --title "SmarterShot $TAG" --notes-file "$OUT/SmarterShot-$TAG.txt"
fi
gh release upload "$TAG" "$OUT/SmarterShot-$TAG.zip" "$OUT/appcast.xml" --repo SmarterTec/SmarterShot --clobber
gh release edit "$TAG" --repo SmarterTec/SmarterShot --draft=false --latest
