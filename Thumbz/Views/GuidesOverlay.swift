import SwiftUI

struct GuidesOverlay: View {
    @Environment(DocumentStore.self) private var store

    var body: some View {
        Canvas { ctx, size in
            if store.showYTCornerRadius {
                // YouTube's thumbnail card rounds at ~12px in the UI; at thumbnail aspect
                // this reads as roughly 1.1% of the width. Draw as a darkening overlay
                // outside the rounded rect to preview what gets masked.
                let radius = size.width * 0.011
                let outer = Path(CGRect(origin: .zero, size: size))
                let inner = Path(roundedRect: CGRect(origin: .zero, size: size),
                                 cornerRadius: radius)
                var cutout = outer
                cutout.addPath(inner)
                ctx.fill(cutout, with: .color(.black.opacity(0.25)), style: FillStyle(eoFill: true))
                ctx.stroke(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: radius),
                           with: .color(.white.opacity(0.6)), lineWidth: 1)
            }

            if store.showRuleOfThirds {
                let style = StrokeStyle(lineWidth: 1)
                let color = Color.white.opacity(0.5)
                for i in 1...2 {
                    let x = size.width * CGFloat(i) / 3
                    ctx.stroke(Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    }, with: .color(color), style: style)
                    let y = size.height * CGFloat(i) / 3
                    ctx.stroke(Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    }, with: .color(color), style: style)
                }
            }

            if store.showGoldenRatio {
                // Phi grid: inverse-phi (0.382) cuts and Fibonacci-ish spiral skeleton
                let phi: CGFloat = 0.618
                let color = Color.yellow.opacity(0.55)
                let style = StrokeStyle(lineWidth: 1)
                let verts: [CGFloat] = [1 - phi, phi]
                let horzs: [CGFloat] = [1 - phi, phi]
                for f in verts {
                    let x = size.width * f
                    ctx.stroke(Path { p in
                        p.move(to: CGPoint(x: x, y: 0))
                        p.addLine(to: CGPoint(x: x, y: size.height))
                    }, with: .color(color), style: style)
                }
                for f in horzs {
                    let y = size.height * f
                    ctx.stroke(Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    }, with: .color(color), style: style)
                }
                // golden spiral (approximated with quarter-arcs on a nested phi-grid)
                drawGoldenSpiral(ctx: ctx, size: size, color: Color.yellow.opacity(0.4))
            }

            if store.showSafeArea {
                // YouTube overlays a gradient + title text across the bottom ~18% on hover
                // and places a channel avatar / chapter markers in certain UIs. Mark the
                // generally-safe middle band.
                let top = size.height * 0.06
                let bottom = size.height * 0.82
                let left = size.width * 0.04
                let right = size.width * 0.96
                let safeRect = CGRect(x: left, y: top, width: right - left, height: bottom - top)
                ctx.stroke(Path(safeRect),
                           with: .color(.cyan.opacity(0.6)),
                           style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }

            if store.showYTBannerSafeAreas {
                drawBannerSafeAreas(ctx: ctx, size: size)
            }
            if store.showPFPCircleMask {
                drawPFPCircle(ctx: ctx, size: size)
            }

            if store.showYTDurationPill {
                // Rounded "12:34" pill, bottom-right corner. ~58x20 pt in YT UI at 320x180
                // thumbnail which is ~18% × 11% of the frame.
                let pillW = size.width * 0.075
                let pillH = size.height * 0.075
                let pad = size.width * 0.012
                let rect = CGRect(x: size.width - pad - pillW,
                                  y: size.height - pad - pillH,
                                  width: pillW, height: pillH)
                ctx.fill(Path(roundedRect: rect, cornerRadius: pillH * 0.25),
                         with: .color(.black.opacity(0.75)))
                ctx.draw(Text("12:34").font(.system(size: pillH * 0.55, weight: .semibold))
                            .foregroundStyle(.white),
                         in: rect)
            }
        }
        .allowsHitTesting(false)
    }

    /// YouTube channel banner safe areas. Banner canvas is 2560×1440. Within
    /// it, content visibility varies by device:
    ///   • TV (full)        2560 × 1440  — entire canvas
    ///   • Desktop          2560 × 423   — middle horizontal strip
    ///   • Tablet           1855 × 423
    ///   • Mobile (safest)  1546 × 423   — center, all-device-visible zone
    /// We render relative to the current canvas size so this works even if the
    /// user picked a non-standard banner resolution.
    private func drawBannerSafeAreas(ctx: GraphicsContext, size: CGSize) {
        let cw = size.width, ch = size.height
        // Treat the canvas as 2560×1440 banner aspect ratio.
        let cy = ch / 2

        // Each zone's HEIGHT relative to 1440: 423/1440 ≈ 0.294
        let zoneH = ch * (423.0 / 1440.0)
        let zoneTop = cy - zoneH / 2
        let zoneBot = cy + zoneH / 2

        // Widths (in canvas pixels)
        let mobileW  = cw * (1546.0 / 2560.0)   // safe on all devices
        let tabletW  = cw * (1855.0 / 2560.0)
        let desktopW = cw                        // full

        // Helper to draw a centered rectangle.
        func zone(width: CGFloat, color: Color, label: String) {
            let x = (cw - width) / 2
            let r = CGRect(x: x, y: zoneTop, width: width, height: zoneBot - zoneTop)
            ctx.stroke(Path(r),
                       with: .color(color),
                       style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
            // Label tucked just inside the upper-left corner.
            let text = Text(label)
                .font(.system(size: max(10, ch * 0.011), weight: .semibold))
                .foregroundStyle(color)
            ctx.draw(text, at: CGPoint(x: x + 6, y: zoneTop + 10), anchor: .topLeading)
        }

        // TV outer (full canvas)
        ctx.stroke(Path(CGRect(x: 0, y: 0, width: cw, height: ch)),
                   with: .color(.purple.opacity(0.6)),
                   style: StrokeStyle(lineWidth: 1.5))
        let tvText = Text("TV / Full Banner 2560×1440")
            .font(.system(size: max(10, ch * 0.011), weight: .semibold))
            .foregroundStyle(.purple.opacity(0.85))
        ctx.draw(tvText, at: CGPoint(x: 6, y: 6), anchor: .topLeading)

        // Desktop strip
        zone(width: desktopW, color: .blue.opacity(0.7), label: "Desktop 2560×423")
        // Tablet
        zone(width: tabletW,  color: .green.opacity(0.7), label: "Tablet 1855×423")
        // Mobile (the safest zone — emphasize)
        zone(width: mobileW,  color: .orange,            label: "Mobile-safe 1546×423 — keep logos & text here")
    }

    /// Profile-picture circle mask. Most platforms (YouTube, Twitter/X, Discord,
    /// Slack, etc.) crop avatars to a circle inscribed in the square canvas.
    /// We darken the area OUTSIDE the circle so the user sees exactly what
    /// will be visible. Also draws an inner "safe ring" at ~92% so logos
    /// and small text don't get clipped by platform borders.
    private func drawPFPCircle(ctx: GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let cx = size.width / 2, cy = size.height / 2
        let outerR = side / 2

        // Dim the corners (what will be cropped off by the circle mask).
        var cutout = Path(CGRect(origin: .zero, size: size))
        cutout.addPath(Path(ellipseIn: CGRect(x: cx - outerR, y: cy - outerR,
                                              width: outerR * 2, height: outerR * 2)))
        ctx.fill(cutout, with: .color(.black.opacity(0.45)), style: FillStyle(eoFill: true))

        // Outline the visible circle in white.
        let outerRect = CGRect(x: cx - outerR, y: cy - outerR, width: outerR * 2, height: outerR * 2)
        ctx.stroke(Path(ellipseIn: outerRect),
                   with: .color(.white.opacity(0.9)),
                   style: StrokeStyle(lineWidth: 1.5))

        // Inner safe ring (logos/text inside this circle are guaranteed safe).
        let safeR = outerR * 0.92
        let safeRect = CGRect(x: cx - safeR, y: cy - safeR, width: safeR * 2, height: safeR * 2)
        ctx.stroke(Path(ellipseIn: safeRect),
                   with: .color(.cyan.opacity(0.7)),
                   style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

        let label = Text("PFP — keep important content inside cyan ring")
            .font(.system(size: max(10, side * 0.012), weight: .medium))
            .foregroundStyle(.white.opacity(0.9))
        ctx.draw(label, at: CGPoint(x: cx, y: cy + outerR + 14), anchor: .top)
    }

    private func drawGoldenSpiral(ctx: GraphicsContext, size: CGSize, color: Color) {
        // Draw 5 nested golden rectangles and quarter-arcs within them.
        var rect = CGRect(origin: .zero, size: size)
        var dir = 0 // 0 = right (big on left), 1 = down, 2 = left, 3 = up
        let phiInverse: CGFloat = 0.618
        var path = Path()
        for _ in 0..<6 {
            let w = rect.width, h = rect.height
            switch dir % 4 {
            case 0:
                // square on left; arc center bottom-right of square
                let sq = CGRect(x: rect.minX, y: rect.minY, width: h, height: h)
                let center = CGPoint(x: sq.maxX, y: sq.maxY)
                path.addArc(center: center, radius: h,
                            startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
                rect = CGRect(x: sq.maxX, y: rect.minY, width: w - h, height: h)
            case 1:
                let sq = CGRect(x: rect.minX, y: rect.minY, width: w, height: w)
                let center = CGPoint(x: sq.minX, y: sq.maxY)
                path.addArc(center: center, radius: w,
                            startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false)
                rect = CGRect(x: rect.minX, y: sq.maxY, width: w, height: h - w)
            case 2:
                let sq = CGRect(x: rect.maxX - h, y: rect.minY, width: h, height: h)
                let center = CGPoint(x: sq.minX, y: sq.minY)
                path.addArc(center: center, radius: h,
                            startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
                rect = CGRect(x: rect.minX, y: rect.minY, width: w - h, height: h)
            default:
                let sq = CGRect(x: rect.minX, y: rect.maxY - w, width: w, height: w)
                let center = CGPoint(x: sq.maxX, y: sq.minY)
                path.addArc(center: center, radius: w,
                            startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
                rect = CGRect(x: rect.minX, y: rect.minY, width: w, height: h - w)
            }
            dir += 1
            _ = phiInverse
            if rect.width < 4 || rect.height < 4 { break }
        }
        ctx.stroke(path, with: .color(color), lineWidth: 1)
    }
}
