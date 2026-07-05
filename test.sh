#!/bin/bash
# Runs SmarterShot's unit tests. Uses a plain executable harness (no XCTest) so
# it works with just the Command Line Tools — no full Xcode required.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"
swift run SmarterShotTests "$@"
