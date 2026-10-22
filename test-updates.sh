#!/bin/bash
# Check the finished bundle and, optionally, a generated signed release package.
set -euo pipefail
cd "$(dirname "$0")"
APP="$PWD/dist/SmarterShot.app"
TOOLS="$PWD/.build/artifacts/sparkle/Sparkle/bin"
FRAMEWORKS="$APP/Contents/Frameworks"
codesign --verify --deep --strict "$APP"
python3 - "$APP" <<'PY'
import base64, pathlib, plistlib, subprocess, sys
app=pathlib.Path(sys.argv[1])
p=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert p['CFBundleIdentifier']=='app.smartershot.SmarterShot'
assert p['SUFeedURL']=='https://github.com/SmarterTec/SmarterShot/releases/latest/download/appcast.xml'
assert p['SUPublicEDKey']==pathlib.Path('update-public-key.txt').read_text().strip()
assert len(base64.b64decode(p['SUPublicEDKey']))==32
assert p['SUVerifyUpdateBeforeExtraction'] and p['SURequireSignedFeed']
assert not p['SUAutomaticallyUpdate'] and not p['SUAllowsAutomaticUpdates']
assert not p['SUEnableSystemProfiling']
expected=pathlib.Path('signing-identity.sha1').read_text().strip().lower()
result=subprocess.run(['codesign','-d','-r-',str(app)],capture_output=True,text=True,check=True)
requirement=result.stdout+result.stderr
assert f'certificate leaf = H"{expected}"' in requirement
assert (app/'Contents/Frameworks/Sparkle.framework/Versions/Current').is_symlink()
print('Bundle validation passed: original privacy identity, embedded framework, signed feed/archive requirements.')
PY
mkdir -p .build/update-tests
swiftc -F "$FRAMEWORKS" -framework Sparkle -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
    Sources/SmarterShot/AppUpdater.swift Tests/Updates/main.swift -o .build/update-tests/UpdateTests
.build/update-tests/UpdateTests "$APP"
if [[ $# -gt 0 ]]; then
    PACKAGE="$(cd "$1" && pwd)"
    "$TOOLS/sign_update" --account app.smartershot.SmarterShot --verify "$PACKAGE/appcast.xml"
    python3 - "$PACKAGE" "$TOOLS/sign_update" <<'PY'
import pathlib, subprocess, sys, tempfile, xml.etree.ElementTree as ET, zipfile, plistlib
folder=pathlib.Path(sys.argv[1]); tool=sys.argv[2]
ns={'s':'http://www.andymatuschak.org/xml-namespaces/sparkle'}
root=ET.parse(folder/'appcast.xml').getroot()
items=root.findall('./channel/item'); assert len(items)==1
item=items[0]; enclosure=item.find('enclosure'); assert enclosure is not None
notes=item.find('description'); assert notes is not None
assert '<h3>' in notes.text and '<ul>' in notes.text and '### Added' not in notes.text, 'Release notes must be rendered HTML, not raw Markdown'
archive=folder/pathlib.PurePosixPath(enclosure.attrib['url']).name
assert enclosure.attrib['url']==f'https://github.com/SmarterTec/SmarterShot/releases/download/{folder.name.removeprefix("update-")}/{archive.name}'
assert archive.stat().st_size==int(enclosure.attrib['length'])
signature=enclosure.attrib['{'+ns['s']+'}edSignature']
subprocess.run([tool,'--account','app.smartershot.SmarterShot','--verify',str(archive),signature],check=True)
with zipfile.ZipFile(archive) as z:
    p=plistlib.loads(z.read('SmarterShot.app/Contents/Info.plist'))
assert item.find('s:version',ns).text==p['CFBundleVersion']
assert item.find('s:shortVersionString',ns).text==p['CFBundleShortVersionString']
assert p['SUPublicEDKey']==pathlib.Path('update-public-key.txt').read_text().strip()
with tempfile.TemporaryDirectory(prefix='smartershot-update-check-') as tmp:
    # Never launch extracted apps. Verify their signature only.
    subprocess.run(['ditto','-x','-k',str(archive),tmp],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',tmp+'/SmarterShot.app'],check=True)
    corrupted=pathlib.Path(tmp)/'corrupted.zip'
    corrupted.write_bytes(archive.read_bytes()+b'corrupted')
    result=subprocess.run([tool,'--account','app.smartershot.SmarterShot','--verify',str(corrupted),signature],capture_output=True)
    assert result.returncode!=0,'Tampered archives must be rejected'
    badfeed=pathlib.Path(tmp)/'appcast.xml'
    badfeed.write_bytes((folder/'appcast.xml').read_bytes().replace(b'<title>',b'<title>TAMPERED ',1))
    result=subprocess.run([tool,'--account','app.smartershot.SmarterShot','--verify',str(badfeed)],capture_output=True)
    assert result.returncode!=0,'Tampered feeds must be rejected'
print('Release validation passed: signed feed, matching versions, signed archive, preserved app signature, tamper rejection.')
PY
fi
