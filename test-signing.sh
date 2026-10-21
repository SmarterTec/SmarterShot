#!/bin/bash
# Run after ./make-app.sh. Exercises the failure cases without modifying the app.
set -euo pipefail
cd "$(dirname "$0")"
python3 - <<'PY'
import hashlib, os, subprocess
from pathlib import Path
bundle=Path('dist/SmarterShot.app')
subprocess.run(['codesign','--verify','--deep','--strict',str(bundle)],check=True)
files=[bundle/'Contents/Info.plist',bundle/'Contents/MacOS/SmarterShot',bundle/'Contents/_CodeSignature/CodeResources']
before=[hashlib.sha256(p.read_bytes()).hexdigest() for p in files]
for value in ['', '0'*40]:
    result=subprocess.run(['./make-app.sh'],env=dict(os.environ,SMARTERSHOT_SIGN_ID=value),text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    assert result.returncode != 0, 'Invalid signing identity was accepted'
    assert [hashlib.sha256(p.read_bytes()).hexdigest() for p in files]==before, 'Preflight failure changed the signed bundle'
    print('PASS: '+('empty fingerprint' if not value else 'unavailable certificate')+' fails without replacing the signed app')
print('Signing checks passed.')
PY
