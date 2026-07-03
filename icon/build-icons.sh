#!/bin/bash
# Renders the SVG icon sources into .icns files (and 1024px previews).
# Requires rsvg-convert and iconutil.
set -euo pipefail
cd "$(dirname "$0")"

build() {
    local svg="$1" out="$2"
    local set="${out%.icns}.iconset"
    rm -rf "$set" && mkdir "$set"
    local r="rsvg-convert"
    $r -w 16   -h 16   "$svg" -o "$set/icon_16x16.png"
    $r -w 32   -h 32   "$svg" -o "$set/icon_16x16@2x.png"
    $r -w 32   -h 32   "$svg" -o "$set/icon_32x32.png"
    $r -w 64   -h 64   "$svg" -o "$set/icon_32x32@2x.png"
    $r -w 128  -h 128  "$svg" -o "$set/icon_128x128.png"
    $r -w 256  -h 256  "$svg" -o "$set/icon_128x128@2x.png"
    $r -w 256  -h 256  "$svg" -o "$set/icon_256x256.png"
    $r -w 512  -h 512  "$svg" -o "$set/icon_256x256@2x.png"
    $r -w 512  -h 512  "$svg" -o "$set/icon_512x512.png"
    $r -w 1024 -h 1024 "$svg" -o "$set/icon_512x512@2x.png"
    iconutil -c icns "$set" -o "$out"
    rm -rf "$set"
    echo "built $out"
}

build SmarterShot.svg      SmarterShot.icns
build SmarterShot-dark.svg SmarterShot-dark.icns
rsvg-convert -w 512 -h 512 SmarterShot.svg      -o SmarterShot-1024.png
rsvg-convert -w 512 -h 512 SmarterShot-dark.svg -o SmarterShot-dark-1024.png
echo "done"
