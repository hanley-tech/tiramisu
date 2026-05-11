# Creator workflows for the GenAI era — 2026

A strategic doc, not a feature list. The point: rethink what an "image
editor" should be when the creator's actual workflow has already moved
to "rough draft → AI reimagine," and traditional tools force a bad
tradeoff between precision and speed.

This doc orients Tiramisu's product direction from v0.6 onward. It
overlaps with /docs/v0.6-roadmap.md (which is the "which models" plan)
but answers a different question: **what is the editor when AI is a
primary input, not a finishing-pass panel?**

---

## The thesis

The creator's actual workflow today, on a YouTube thumbnail / IG cover /
podcast art / product shot:

1. **Rough composition.** Drop in a face screenshot, type a headline,
   block out the subject with shapes, paste a stock photo — anything
   that captures *intent* and rough placement.
2. **AI reimagines it.** Describe the vibe ("epic reaction face,
   cinematic lighting, dark blue gradient background, retro arcade
   text"), feed the rough comp as a reference, get back a polished
   render that often beats anything they could've made manually.
3. **Pick + iterate.** Generate variations, cherry-pick, maybe nudge
   composition and re-roll, sometimes finish a detail by hand.

Existing tools force a bad tradeoff at step 2:

| Tool                | Precision     | Speed    | Editable result | Layer structure |
|---------------------|---------------|----------|-----------------|-----------------|
| Photoshop           | High          | Slow     | Yes             | Yes             |
| Midjourney / SDXL   | Low (prompt only) | Fast | Output only     | No              |
| Krea / Magnific     | Medium (img2img one-shot) | Fast | Limited | Lost on gen     |
| Adobe Firefly panel | Low–medium    | Slow     | Yes (in PS)     | Yes (cloud-bound) |

**Tiramisu's structural opening:** be the first editor where:

- Your rough composition (layered, on-canvas, in your file) is the
  *input*, not a separate reference image.
- "Reimagine" produces a polished result as **a new editable layer**
  (or a stack via Auto-Layer). Your draft is preserved, you can iterate.
- The whole loop — sketch → reimagine → tweak → re-roll — happens
  inside one document, on-device, fast.

This is "Cursor for image editing." Cursor didn't replace VS Code; it
absorbed VS Code and added a new primary mode (chat → diff) on top of
the file-tree-and-tabs world. Tiramisu can do the same: keep the
layers / tools / brush / selection world Photoshop trained everyone in,
add a primary "Reimagine" mode on top.

---

## Why this is now possible

Three things changed in 2025–2026 that didn't exist when Photoshop's UX
was last rethought:

1. **Strong open-weight image models that run on Apple Silicon.**
   FLUX.2, SD 3.5, SDXL-Lightning all hit acceptable quality on M-series
   Macs in seconds, not minutes. The local + fast prerequisite is met.
2. **Image-to-image with strength control is solved.** Latent inversion,
   ControlNet, IP-Adapter, T2I-Adapter. We can preserve composition
   (where things are) while replacing style + texture (what they look
   like). This is the technical backbone of "reimagine my draft."
3. **Layer decomposition exists.** Qwen-Image-Layered (Dec 2025) means
   the output of a reimagine doesn't have to be a flat raster — it can
   be a multi-layer document. The result is *more* editable than the
   input.

A 2024 version of this product would've shipped as a cloud SaaS with a
panel called "AI." A 2026 version ships as a layered native editor with
AI as a peer tool.

---

## Concrete creator features

### Tier 1 — Reimagine loop (the headline)

These are the features that turn the thesis into a daily workflow.

**Reimagine Canvas** — `⌘⇧R`
- Take the entire canvas (or active layer) → run img2img against
  FLUX.2 (or LocalFlux v2) with adjustable strength.
- Strength slider: 0% = photocopy (no-op), 50% = composition preserved
  but style fully replaced, 100% = pure prompt-to-image.
- Result lands as a **new layer** above the current stack. Your draft
  is untouched.
- Same prompt + canvas-as-reference workflow, every time. No "import
  / export to a different app" loop.

**Reimagine Selection**
- Same as above, but scoped to `selectionPath`. Replace the selected
  region while keeping everything outside it pixel-identical.
- Different from generative *fill* (which paints into a hole) — this
  reimagines what's already there.

**Variations** — `⌘⇧V`
- Generate N parallel variations (default 4) of a Reimagine. Show in
  a chooser sheet; one click promotes the chosen variant to a layer,
  rest are saved as collapsed siblings the user can reveal later.
- Powered by varying the seed at fixed strength + prompt.

**Lineage panel**
- Each Reimagine creates a node in a tree visible in a side panel.
  Roots = initial drafts; children = generations; siblings = variants.
- Click any node → the canvas snaps to that state. Continue branching.
- Fixes the "I got something good 5 generations ago and now I can't
  get back" problem that makes creators hesitant to iterate.

### Tier 2 — Composition controls

What makes Reimagine *trustworthy* for creators is preserving the
parts they care about across generations.

**Subject lock**
- Mark a layer (face, product, logo) as "subject." Reimagine preserves
  pixel-level identity for subjects via IP-Adapter or face-id models.
  The world around them changes; they don't.
- Massive for thumbnail workflows where the creator's face needs to
  stay *their* face across 12 variants.

**Style reference**
- Drop another image as a "style reference" panel. Reimagine adopts
  its mood / palette / lighting without copying its content.
- Powered by IP-Adapter (style mode) or B-LoRA.

**Pose / depth lock**
- Take the current canvas's depth map (we already compute it for
  StudioRelight via Depth Anything 3) → feed it to ControlNet-Depth
  during Reimagine so spatial layout is preserved exactly.
- Killer combo with Auto-Layer: "reimagine each layer in this style,
  preserving its depth and z-order."

### Tier 3 — Domain templates

Creators don't make "an image"; they make "a YouTube thumbnail" or
"an Instagram carousel." We should ship the canvas presets, brand
overlays, and Reimagine recipes for the platforms that matter.

**Platform presets** (extends the existing Welcome Window options):
- YouTube thumbnail (1280×720) — already have safe-area / duration pill
  / banner overlays.
- YouTube end-screen (1280×720, with end-screen safe areas).
- Instagram post 1:1 / story 9:16 / reel cover 9:16.
- TikTok cover 9:16.
- Podcast cover 1:1, 3000×3000.
- Substack / Ghost header 1500×500.
- X / LinkedIn / Facebook OG card 1200×630.
- App icon 1024×1024 (with iOS / macOS rounded-rect previews).

**Reimagine recipes** — preset prompt + style + composition for common
formats:
- "Tech reaction thumbnail" (face + product on dark gradient).
- "Explainer with arrow + headline" (clean composition, big text, arrow).
- "Before / after split."
- "Cinematic product hero" (soft lighting, depth, dramatic).
- "Y2K poster" (gradients, retro typography, glow).
- Each recipe is a JSON file (matches our Tier 1 marketplace plan from
  the extensibility doc) — community can publish their own.

**Multi-platform export**
- One render → all platform sizes. Smart crop based on subject lock.
  Generate 8 variants for the 8 platforms in one click.
- Replaces 80% of the manual "now save it for IG, now save for X, now
  save for the email header" tedium.

### Tier 4 — The high-bar creator features

Not v0.6 / v0.7 territory, but worth knowing exists so we don't paint
ourselves into a corner architecturally.

**Real-time canvas (Krea-style)**
- Every brush stroke / move / text edit triggers a low-quality
  Reimagine that updates within ~200ms. The artist paints + AI keeps
  rendering. Massive flow-state experience.
- Requires a small fast model running on the Neural Engine + careful
  cache invalidation. Probably v1.0+.

**Voice / text → composition**
- Type or say "tech reaction thumbnail with a phone, big arrow, white
  background, my face on the right" → AI lays out a rough comp with
  shapes + placeholder layers. User refines, then Reimagines.
- Foundation Models framework + a layout-prediction prompt.

**Style packs (community marketplace)**
- Creators upload their style as a downloadable pack (LoRA + reference
  images + recipe JSONs). Other creators apply with one click.
- "Mr Beast thumbnail style", "Marques Brownlee product shot",
  "Casey Neistat vlog cover." Each pack is a marketplace SKU.
- Plays directly to the existing v3+ marketplace plan.

**A/B testing integration**
- Push N thumbnail variants to YouTube via the official Thumbnails A/B
  Testing API. Track which one performs best, feed back into next
  Reimagine session.

---

## Strategic positioning

### What we're not

Not "another diffusion UI." ComfyUI / Automatic1111 / Forge already
exist for that audience. They're powerful but require a node-graph
mental model that most creators don't have time for.

Not "a chat-with-your-image app." Adobe is doing this; so is everyone
else. The chat surface is a feature, not a product.

### What we are

The native macOS editor where:

- Layers + selection + paint are first-class (Photoshop's primitives,
  on Apple Silicon).
- Reimagine is also first-class — same speed of iteration as the
  brush tool, on the same canvas, producing the same kind of editable
  output.
- The marketplace for prompts / recipes / style packs is the moat —
  creators teaching creators how to use the tool.

### Tagline candidates

- "Image editor for the rough-draft era."
- "Sketch it. Reimagine it. Ship it."
- "Photoshop-class layers, AI-class speed."
- "The native editor where AI is a peer, not a panel."

(Pick one when we ship Reimagine in v0.6 and update the hero.)

---

## Suggested release shape

| Release | Theme            | Headline features                                                    |
|---------|------------------|----------------------------------------------------------------------|
| v0.5.0  | Paint + Selection (shipped)| Pencil/eraser, lasso family, magic wand, Smart Select, refine edge |
| v0.6.0  | The AI release   | Auto-Layer (Qwen) + Smart Select 2 (SAM 3) + **Reimagine v0** (canvas + selection)        |
| v0.6.1  | Composition controls | Subject lock + style reference + depth lock                       |
| v0.7.0  | Domain templates | Platform presets + Reimagine recipes + multi-platform export        |
| v0.7.x  | Drop-in upgrades | RMBG 2.0, FLUX.2, DA3, Magic Eraser, AI Upscale, Restore Faces      |
| v0.8+   | Lineage + variations panel + Foundation Models prompt helper        |
| v1.0    | Real-time canvas + style pack marketplace                           |

The key revision vs the previous plan: **Reimagine v0 belongs in v0.6**
alongside Auto-Layer. Together they form a coherent "the AI release"
story: drop in any image → Auto-Layer separates it → Reimagine
re-renders any layer or the whole canvas → Smart Select 2 picks any
object by click or text. That's the narrative.

---

## Sources / inspirations

- **Krea AI** real-time canvas — [krea.ai](https://www.krea.ai/) — sets
  the bar for live img2img feedback loops.
- **Magnific** — [magnific.ai](https://magnific.ai/) — proves there's a
  premium market for high-quality img2img.
- **Cursor** product playbook — absorbing the existing tool's UX while
  adding a new primary mode that becomes load-bearing.
- **Adobe Firefly Reference Image** — Adobe's belated answer to img2img;
  shows where the incumbent thinks the puck is going.
- **Recraft** — vector + AI hybrid, proves creators want layered output
  from generation, not flat rasters.
- **IP-Adapter / ControlNet / T2I-Adapter** — the technical primitives
  that make subject lock + style reference + depth lock practical.
