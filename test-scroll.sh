#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/scroll-tests
swiftc -emit-module -emit-library -module-name SmarterShotCore Sources/SmarterShotCore/ScrollImageMatcher.swift -o .build/scroll-tests/libSmarterShotCore.dylib -emit-module-path .build/scroll-tests/SmarterShotCore.swiftmodule
swiftc -I .build/scroll-tests -L .build/scroll-tests -lSmarterShotCore -Xlinker -rpath -Xlinker "$PWD/.build/scroll-tests" Sources/SmarterShot/ScrollCaptureEngine.swift Tests/ScrollCapture/main.swift -o .build/scroll-tests/ScrollTests
.build/scroll-tests/ScrollTests
