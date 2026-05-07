#!/usr/bin/env bash
# generate-test-report.sh — produce a self-contained HTML report from an
# xcresult bundle.
#
# Usage:
#   scripts/generate-test-report.sh <xcresult-bundle> <output-html>
#
# Reads test-results from the given xcresult, extracts attachments (UI test
# screenshots, etc.), reads doc-comments from test source files, and writes
# a single HTML file with everything inlined as base64.

set -euo pipefail

if [[ $# -lt 2 ]]; then
  echo "usage: $0 <xcresult-bundle> <output-html>" >&2
  exit 64
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec /usr/bin/env python3 "$SCRIPT_DIR/generate-test-report.py" "$@"
