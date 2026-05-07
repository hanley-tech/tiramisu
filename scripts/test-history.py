#!/usr/bin/env python3
"""Tests for scripts/generate-history.py — the dashboard-builder parser.

The dashboard's correctness depends on `parse_report` extracting the right
data from filenames + report HTML. Regressions there silently corrupt the
test history without crashing. This file pins down the parser behavior
with a small synthetic-report harness.

Run: `python3 scripts/test-history.py` (exits non-zero on failure)
"""
from __future__ import annotations

import importlib.util
import sys
import tempfile
from datetime import datetime
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parent


def load_module():
    """Load generate-history.py by file path (its filename has a hyphen,
    so plain `import` doesn't work)."""
    spec = importlib.util.spec_from_file_location(
        "generate_history", SCRIPT_DIR / "generate-history.py"
    )
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def synthetic_report(passed: int, failed: int, skipped: int,
                     suites: int, env: str = "Tiramisu", duration_s: float = 6.4) -> str:
    """Build a minimal HTML report that looks like what generate-test-report
    actually emits — same stat block markup, same meta line shape."""
    return f"""<!doctype html>
<html><head><title>Test report</title></head><body>
<header class="top">
  <div class="meta">
    {env} · ran 2026-05-07 12:00:00 · {duration_s:.2f}s · branch <code>main</code>
  </div>
  <div class="stats">
    <div class="stat ok"><div class="num">{passed}</div><div class="lbl">Passed</div></div>
    <div class="stat fail"><div class="num">{failed}</div><div class="lbl">Failed</div></div>
    <div class="stat skip"><div class="num">{skipped}</div><div class="lbl">Skipped</div></div>
    <div class="stat"><div class="num">{suites}</div><div class="lbl">Suites</div></div>
  </div>
</header>
</body></html>"""


# ─── tests ──────────────────────────────────────────────────────────────

PASS = 0
FAIL = 0


def check(label: str, ok: bool, detail: str = "") -> None:
    global PASS, FAIL
    if ok:
        PASS += 1
        print(f"  \033[32m✓\033[0m {label}")
    else:
        FAIL += 1
        print(f"  \033[31m✗\033[0m {label}{(' — ' + detail) if detail else ''}")


def run_tests(mod) -> int:
    print("Test: parse_report extracts data from a well-formed report")
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        p = tmpdir / "2026-05-07T12-15-10-c9f26c5-passed.html"
        p.write_text(synthetic_report(passed=28, failed=0, skipped=0,
                                       suites=8, duration_s=6.4))
        info = mod.parse_report(p)
        check("returns dict", info is not None)
        check("filename roundtrip", info["filename"] == p.name)
        check("timestamp parsed", info["ts"] == datetime(2026, 5, 7, 12, 15, 10),
              detail=str(info["ts"]))
        check("sha extracted", info["sha"] == "c9f26c5", detail=str(info["sha"]))
        check("result extracted", info["result"] == "passed",
              detail=str(info["result"]))
        check("passed count", info["passed"] == 28, detail=str(info["passed"]))
        check("failed count", info["failed"] == 0)
        check("skipped count", info["skipped"] == 0)
        check("suites count", info["suites"] == 8)
        check("duration parsed", info["duration"] == 6.4,
              detail=f"got {info['duration']}")

    print("\nTest: parse_report extracts a failure case correctly")
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        p = tmpdir / "2026-05-08T09-30-00-abcdef1-failed.html"
        p.write_text(synthetic_report(passed=25, failed=3, skipped=1,
                                       suites=8, duration_s=12.7))
        info = mod.parse_report(p)
        check("result is failed", info["result"] == "failed")
        check("3 failed extracted", info["failed"] == 3)
        check("1 skipped extracted", info["skipped"] == 1)

    print("\nTest: malformed filenames are rejected")
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        bad_names = [
            "2026-05-07-c9f26c5-passed.html",       # missing TIME segment
            "12-15-10-c9f26c5-passed.html",          # missing date
            "2026-05-07T12-15-10-c9f26c5.html",      # missing -passed/-failed
            "2026-05-07T12-15-10-c9f26c5-flaky.html",  # unknown result
            "random-junk.html",
        ]
        for n in bad_names:
            p = tmpdir / n
            p.write_text(synthetic_report(28, 0, 0, 8))
            info = mod.parse_report(p)
            check(f"rejects {n!r}", info is None,
                  detail=f"unexpectedly parsed: {info}")

    print("\nTest: stat block regex tolerates whitespace variations")
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        p = tmpdir / "2026-05-07T12-15-10-c9f26c5-passed.html"
        # Same numbers but with extra whitespace + different element ordering
        weird_html = """<!doctype html><body>
<div class="stat ok">
  <div class="num">99</div>

  <div class="lbl">Passed</div>
</div>
<div class="stat fail"><div class="num">2</div><div class="lbl">Failed</div></div>
<div class="meta"> Tiramisu · ran X · 11.11s · branch main</div>
</body></html>"""
        p.write_text(weird_html)
        info = mod.parse_report(p)
        check("99 passed across whitespace", info["passed"] == 99,
              detail=str(info["passed"]))
        check("2 failed across whitespace", info["failed"] == 2)
        check("duration parsed across whitespace", info["duration"] == 11.11,
              detail=str(info["duration"]))

    print("\nTest: render() handles empty + populated histories")
    with tempfile.TemporaryDirectory() as tmp:
        tmpdir = Path(tmp)
        # Empty case
        empty_html = mod.render([])
        check("empty render mentions 'No test reports yet'",
              "No test reports yet" in empty_html)
        # Populated case
        runs = [
            {
                "filename": "2026-05-07T12-15-10-c9f26c5-passed.html",
                "ts": datetime(2026, 5, 7, 12, 15, 10),
                "sha": "c9f26c5",
                "result": "passed",
                "passed": 28, "failed": 0, "skipped": 0, "suites": 8,
                "duration": 6.4,
            },
            {
                "filename": "2026-05-06T08-00-00-deadbee-failed.html",
                "ts": datetime(2026, 5, 6, 8, 0, 0),
                "sha": "deadbee",
                "result": "failed",
                "passed": 25, "failed": 3, "skipped": 0, "suites": 8,
                "duration": 12.7,
            },
        ]
        out = mod.render(runs)
        check("render contains both shas",
              "c9f26c5" in out and "deadbee" in out)
        check("render contains both filenames",
              "2026-05-07T12-15-10-c9f26c5-passed.html" in out
              and "2026-05-06T08-00-00-deadbee-failed.html" in out)
        check("render shows correct pass/fail glyphs",
              ">✓<" in out and ">✗<" in out)
        check("render shows latest summary card",
              'class="latest"' in out)

    print(f"\n{PASS} passed, {FAIL} failed")
    return 0 if FAIL == 0 else 1


if __name__ == "__main__":
    mod = load_module()
    sys.exit(run_tests(mod))
