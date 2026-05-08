# Test fixtures — attribution

Test inputs for `ShowcaseThumbnailTests`, `SmartObjectIntegrationTests`,
the snapshot galleries (`AdjustPresetSnapshotTests`, `BlendModeSnapshotTests`,
`FilterSnapshotTests`, `LayerStyleSnapshotTests`, `RelightSnapshotTests`,
`TextLayerSnapshotTests`), and the color/mask suites
(`HSLSnapshotTests`, `HSLBandIsolationTests`, `LayerMaskSnapshotTests`).

## Source

| Local file       | Source                                | Subject                                | License             |
|------------------|---------------------------------------|----------------------------------------|---------------------|
| `sunset.jpg`     | `picsum.photos/seed/face/540/720`     | Beach at sunset                        | Unsplash            |
| `cafe.jpg`       | `picsum.photos/seed/creator/540/720`  | Urban cafe                             | Unsplash            |
| `clouds.jpg`     | `picsum.photos/seed/tech/540/720`     | Bird in clouds                         | Unsplash            |
| `kodim23.png`    | `r0k.us/graphics/kodak/kodak/kodim23.png` | Two macaws (color test reference) | Kodak public domain |
| `kodim15.png`    | `r0k.us/graphics/kodak/kodak/kodim15.png` | Child portrait (BG-removal test)  | Kodak public domain |

## Licenses

**Unsplash** ([license](https://unsplash.com/license)): photos are free for
commercial and non-commercial use, no permission needed.

**Kodak True Color suite** (kodim##.png): historical industry-standard color
test images released to the public domain by Kodak. The Kodim suite is
the canonical reference set for color-pipeline regression in image-processing
literature; it's used here for the same purpose plus Vision foreground
segmentation tests on the portrait.

These fixtures are committed to the repo so tests run reproducibly
without network access.
