#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/markup-tests
swiftc Sources/SmarterShot/MarkupWindow.swift Tests/Markup/main.swift -o .build/markup-tests/MarkupTests
.build/markup-tests/MarkupTests
