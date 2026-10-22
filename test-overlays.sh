#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/overlay-tests
swiftc Sources/SmarterShot/OverlayWindow.swift Sources/SmarterShot/DraggableImageView.swift Tests/Overlays/main.swift -o .build/overlay-tests/OverlayTests
.build/overlay-tests/OverlayTests
