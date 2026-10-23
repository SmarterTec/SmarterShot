#!/bin/bash
# Headless file/metadata/filename checks; no windows, captures or AI execution.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/capture-source-tests
swiftc -parse-as-library Sources/SmarterShot/CaptureSourceContext.swift Sources/SmarterShot/ScreenshotAIService.swift Tests/CaptureSource/main.swift -o .build/capture-source-tests/SourceTests
.build/capture-source-tests/SourceTests
