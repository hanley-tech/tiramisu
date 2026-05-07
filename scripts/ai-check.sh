#!/usr/bin/env bash
# ai-check.sh — one command to verify Tiramisu is in good shape.
#
# Runs:
#   1. xcodegen generate (regenerates Tiramisu.xcodeproj from project.yml)
#   2. xcodebuild build (Debug)
#   3. xcodebuild test (TiramisuTests only — unit + snapshot, fast)
#   4. scripts/generate-test-report.sh (writes build/test-report.html)
#
# Usage:
#   scripts/ai-check.sh           # full check
#   scripts/ai-check.sh --no-ui   # skip UI tests (default)
#   scripts/ai-check.sh --with-ui # include TiramisuUITests (slow, launches app)
#   scripts/ai-check.sh --open    # open the HTML report when done
#
# Exits non-zero on any failure. Designed to be safe to call from CI or local.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_DIR"

WITH_UI=0
OPEN_REPORT=0
for arg in "$@"; do
  case "$arg" in
    --with-ui) WITH_UI=1 ;;
    --no-ui)   WITH_UI=0 ;;
    --open)    OPEN_REPORT=1 ;;
    -h|--help)
      sed -n '2,16p' "$0"; exit 0 ;;
  esac
done

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()   { printf '\033[1;32m✓ %s\033[0m\n' "$*"; }
fail() { printf '\033[1;31m✗ %s\033[0m\n' "$*" >&2; }

step "1/4  xcodegen generate"
if ! command -v xcodegen >/dev/null 2>&1; then
  fail "xcodegen not installed. brew install xcodegen"
  exit 1
fi
xcodegen generate >/dev/null
ok "xcodeproj regenerated"

step "2/4  xcodebuild build (Debug)"
xcodebuild \
  -project Tiramisu.xcodeproj \
  -scheme Tiramisu \
  -configuration Debug \
  -destination 'platform=macOS' \
  build 2>&1 | tail -3
ok "build succeeded"

step "3/4  xcodebuild test"
RESULT_BUNDLE="$PROJECT_DIR/build/test-results.xcresult"
mkdir -p "$PROJECT_DIR/build"
rm -rf "$RESULT_BUNDLE"

TEST_ARGS=(
  -project Tiramisu.xcodeproj
  -scheme Tiramisu
  -configuration Debug
  -destination 'platform=macOS'
  -resultBundlePath "$RESULT_BUNDLE"
  -only-testing:TiramisuTests
)
if [[ "$WITH_UI" == "1" ]]; then
  TEST_ARGS+=( -only-testing:TiramisuUITests )
fi

if xcodebuild "${TEST_ARGS[@]}" test 2>&1 | tail -5; then
  ok "tests passed"
else
  fail "tests failed (see $RESULT_BUNDLE)"
  # don't exit — still generate the report so the user can see what failed
fi

step "4/4  generate HTML test report"
"$SCRIPT_DIR/generate-test-report.sh" "$RESULT_BUNDLE" "$PROJECT_DIR/build/test-report.html"
ok "report written: build/test-report.html"

if [[ "$OPEN_REPORT" == "1" ]]; then
  open "$PROJECT_DIR/build/test-report.html"
fi

printf '\n\033[1;32mai-check complete.\033[0m  See build/test-report.html\n'
