#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/selection-tests
swiftc -emit-module -emit-library -module-name SmarterShotCore Sources/SmarterShotCore/*.swift -o .build/selection-tests/libSmarterShotCore.dylib -emit-module-path .build/selection-tests/SmarterShotCore.swiftmodule
swiftc -I .build/selection-tests -L .build/selection-tests -lSmarterShotCore -Xlinker -rpath -Xlinker "$PWD/.build/selection-tests" Sources/SmarterShot/SelectionOverlay.swift Tests/Selection/main.swift -o .build/selection-tests/SelectionTests
.build/selection-tests/SelectionTests
