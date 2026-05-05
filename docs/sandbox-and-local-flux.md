# Sandbox & Local FLUX-Fill backend

## TL;DR

The Thumbz target is **not sandboxed**. This is a deliberate choice driven by the Local FLUX-Fill backend, which spawns the user-installed `mflux-generate-fill` subprocess.

## Why sandbox is off

`Thumbz.entitlements` only declares `com.apple.security.network.client`. There is no `com.apple.security.app-sandbox` entitlement.

Sandbox would block this feature for two reasons:

1. **Cannot execute arbitrary user-path binaries.** A sandboxed app can't `Process.run` a binary at `~/.local/bin/mflux-generate-fill` without an explicit `temporary-exception.files.absolute-path.read-only` entitlement listing that path — and that path varies per user installation method (uv vs pip vs custom).
2. **Subprocesses inherit the parent's sandbox.** Even if execution succeeded, `mflux-generate-fill` would itself be sandboxed and unable to:
   - Read its HuggingFace cache (typically `~/.cache/huggingface` or wherever `HF_HOME` points)
   - Read the user's HF token
   - Read its model weights from `/Volumes/T9/...` (or any external/non-default volume)

## Distribution implications

| Channel | Sandbox required | Affected |
|---|---|---|
| Mac App Store | Yes | This build is NOT eligible |
| Developer ID + DMG / PKG / direct download | No | Unaffected |
| Notarization | No | Unaffected — notarization checks signing/hardened-runtime, not sandbox |
| Helper / extension | Yes | Out of scope |

For Thumbz, the intended distribution is direct DMG + Developer ID. This is fine.

## If we later need a Mac App Store build

Two options:

1. **Two builds.** A "Pro/Direct" target with sandbox off that includes the Local FLUX-Fill backend, and a "MAS" target with sandbox on where Settings hides the FLUX-Fill option (force-falls-back to Replicate or local 9ch SD). Both share the same source; differ only in `project.yml` target entries.
2. **Privileged XPC helper.** The main app stays sandboxed; a separate non-sandboxed helper hosts the subprocess spawn. More architecture, but MAS-distributable. Days of work.

## What still works without sandbox

Everything we relied on sandbox for previously is still fine:

- `FileBookmarks.swift` — `URL.bookmarkData(options: [.withSecurityScope])` and `startAccessingSecurityScopedResource()` continue to work without sandbox; they're a no-op pair on non-sandboxed apps. Code didn't need changes.
- File open / save panels work without `user-selected.read-write` because that entitlement is only meaningful inside a sandbox.
- Network calls (Replicate, model downloads) work without `network.client`.

## What the Local FLUX-Fill backend does

See `Thumbz/Rendering/LocalFluxFillService.swift`.

- Detects `~/.local/bin/mflux-generate-fill` at runtime.
- Auto-prefers it for Expand mode if installed (over Local SD-1.5 9ch and Local SD-1.5 i2i).
- For each Expand pass: writes the prepared canvas image + the outpaint mask to a temp dir, spawns mflux as a subprocess, streams progress back to the UI, reads the output PNG, returns the `CGImage` to the Coordinator.
- Default config: 20 steps, guidance 30, Q4 quantization. Roughly ~2 minutes per Expand on M1 Max once the model is cached.
- License note: FLUX.1-Fill-dev is **non-commercial**. We never ship the weights. Users opt in for personal use.
