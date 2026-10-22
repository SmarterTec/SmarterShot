#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/ai-tests
swiftc -target arm64-apple-macos13.0 Sources/SmarterShot/ScreenshotAIService.swift \
    Sources/SmarterShot/AITesterWindow.swift Tests/AI/main.swift -o .build/ai-tests/AITests
.build/ai-tests/AITests "$@"
