#!/bin/bash
# Pure orchestration only: never launches Chrome, creates windows or sends input.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/chrome-tests
swiftc -parse-as-library Sources/SmarterShot/ChromeCaptureEngine.swift Tests/ChromeCapture/main.swift -o .build/chrome-tests/ChromeTests
.build/chrome-tests/ChromeTests
