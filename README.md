<h1 align="center">Tiramisu</h1>

<p align="center">
  <strong>Free, open-source, AI-native image editor for macOS.</strong><br/>
  Made for creators — not graphic designers.
</p>

<p align="center">
  <a href="https://tiramisu.hanley.world">tiramisu.hanley.world</a> ·
  <a href="https://tiramisu.hanley.world/getting-started.html">Getting started</a> ·
  <a href="https://tiramisu.hanley.world/branding.html">Brand kit</a>
</p>

---

## Status

🚧 **Pre-release · v0.1 in active development.**
The app builds and runs; the AI-native intent bar and the YouTube-thumbnail end-to-end workflow are being polished before the first signed DMG ships. Star or watch to get notified.

## What is it

A real layered image editor — like Photoshop, but free, open, native to Apple Silicon, and with AI woven through the editing surface from day one (not bolted on as a panel).

- **Layered editing** with Photoshop-familiar shortcuts (`V`, `T`, `Cmd+T`, `Cmd+J`, `[ / ]`, `Cmd+0`, …)
- **AI-native** — generative fill, expand, replace, remove; intent bar at the canvas (v0.1)
- **Mac-native** — Swift 6, Liquid Glass, Apple Silicon, on-device generation via [mflux](https://github.com/filipstrand/mflux)
- **Built for creators** — every platform's safe-area baked in; cross-post auto-relayout; brand kits; native `.tiramisu` document type
- **Free, forever** — open source under AGPL-3.0 (pending). No subscription. No Pro tier.

For the full vision + strategy + design direction, see **[tiramisu.hanley.world](https://tiramisu.hanley.world)**.

## Screenshots

> Coming with v0.1. Watch this space.

## Requirements

| | Minimum |
|---|---|
| macOS | 26.0 (Tahoe) |
| Hardware | Apple Silicon (M1+) |
| Xcode | 17.0+ |
| xcodegen | `brew install xcodegen` |

## Build &amp; run

```bash
git clone https://github.com/hanley-tech/tiramisu.git
cd tiramisu
xcodegen generate
open Tiramisu.xcodeproj   # then ⌘R in Xcode
```

For a step-by-step walkthrough see **[Getting started](https://tiramisu.hanley.world/getting-started.html)**.

## AI backends

Two options. Pick one in **AI → Generative Fill Settings**.

| Backend | Setup | Cost | Privacy |
|---|---|---|---|
| **Replicate** (cloud) | Paste API key in Settings | Pay-per-generation | Image leaves your Mac |
| **Local FLUX-Fill** | `./scripts/bootstrap.sh` (once) | Free | 100% on-device |

The bootstrap script handles the whole Local FLUX-Fill setup end-to-end (`uv` → `mflux` → Hugging Face auth → ~24 GB model fetch → verify). Idempotent; safe to re-run.

```bash
./scripts/bootstrap.sh                # full setup
./scripts/bootstrap.sh --skip-download # defer the 24GB pull
./scripts/bootstrap.sh --help         # show all flags
```

If FLUX-Fill isn't installed when you try a generative fill, the app prompts you to either run the bootstrap or fall back to Replicate. No dead ends.

## Project layout

```
Tiramisu/                 — Swift source
  Models/                 — DocumentStore, PXLayer, Snapshot, Log, Bookmarks
  Rendering/              — LayerRenderer, GenerativeFill*, ControlServer, …
  Views/                  — SwiftUI + AppKit interop, panels, overlays
  Resources/              — Info.plist, Assets.xcassets, entitlements
project.yml               — XcodeGen spec — `xcodegen generate` rebuilds .xcodeproj
scripts/
  bootstrap.sh            — installs Local FLUX-Fill end-to-end
  install-global.sh       — Debug post-build hook; installs to ~/Applications
CLAUDE.md                 — agent / contributor onboarding
```

The marketing site (10 HTML pages, brand kit, design docs) lives in a separate repo: **[hanley-tech/tiramisu_www](https://github.com/hanley-tech/tiramisu_www)**.

## License

To be finalized — likely **AGPL-3.0** (protects against fork-and-resell as a closed product). Until the LICENSE file lands, treat as "all rights reserved" pending license selection.

## Contributing

Issues, ideas, and PRs welcome. Code conventions and review process will land in `CONTRIBUTING.md`. For now:

- File issues at [github.com/hanley-tech/tiramisu/issues](https://github.com/hanley-tech/tiramisu/issues)
- See `CLAUDE.md` for repo conventions (xcodegen-only, no in-tree edits to `.xcodeproj`, etc.)
- Build with the steps above; PRs that break `xcodebuild build` won't be merged

## Acknowledgements

- [mflux](https://github.com/filipstrand/mflux) — FLUX-Fill inference on Apple Silicon
- [RichTextKit](https://github.com/danielsaidi/RichTextKit) — text editing primitives
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — keeps the project file diff-able

---

<p align="center">
  <sub>Built in San Francisco · 2026</sub>
</p>
