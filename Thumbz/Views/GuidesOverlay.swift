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
