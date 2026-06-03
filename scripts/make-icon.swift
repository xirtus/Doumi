#!/usr/bin/swift
/// Doumi icon — cute folder character, sticker style
/// Layout: back folder (tab + dot visible) behind front folder (face: || — / — ○)
import AppKit
import Foundation

let iconsetPath = "/tmp/doumi.iconset"
let fm = FileManager.default
try? fm.removeItem(atPath: iconsetPath)
try! fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

// MARK: - Render single icon at given pixel dimension

func makeIcon(px: Int) -> Data {
    let s = CGFloat(px)
    let cs = CGColorSpaceCreateDeviceRGB()

    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: NSColorSpaceName.deviceRGB,
        bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0)!

    NSGraphicsContext.saveGraphicsState()
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    gc.shouldAntialias = true
    NSGraphicsContext.current = gc
    let ctx = gc.cgContext

    // ── Coordinate system: (0,0) = top-left, y increases downward ──

    let white  = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
    let shadow = CGColor(srgbRed: 0.28, green: 0.20, blue: 0.52, alpha: 0.30)

    // ── 1. Background: very soft lavender-white gradient ───────────
    let bg = CGGradient(colorsSpace: cs, colors: [
        CGColor(srgbRed: 0.938, green: 0.934, blue: 0.968, alpha: 1),
        CGColor(srgbRed: 0.898, green: 0.892, blue: 0.948, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg,
        start: CGPoint(x: 0, y: 0), end: CGPoint(x: s, y: s), options: [])

    // ── HELPERS ────────────────────────────────────────────────────

    /// Pill (fully-rounded rect): origin at center
    func pill(cx: CGFloat, cy: CGFloat, w: CGFloat, h: CGFloat) -> CGPath {
        let r = min(w, h) / 2
        return CGPath(roundedRect:
            CGRect(x: cx - w/2, y: cy - h/2, width: w, height: h),
            cornerWidth: r, cornerHeight: r, transform: nil)
    }

    /// Draw sticker shape: drop-shadow → white border → gradient fill
    func sticker(path: CGPath,
                 c0: CGColor, c1: CGColor,
                 from: CGPoint, to: CGPoint,
                 bw: CGFloat) {

        // Drop shadow (paint the shape opaque to cast shadow, will be covered)
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: s * 0.005, height: s * 0.022),
                      blur: s * 0.052, color: shadow)
        ctx.addPath(path); ctx.setFillColor(c0); ctx.fillPath()
        ctx.restoreGState()

        // White border stroke (half inside / half outside path)
        ctx.addPath(path)
        ctx.setStrokeColor(white)
        ctx.setLineWidth(bw * 2)
        ctx.setLineJoin(.round)
        ctx.strokePath()

        // Gradient fill (covers inside portion of stroke, leaving outer bw as white)
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        let g = CGGradient(colorsSpace: cs, colors: [c0, c1] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: from, end: to, options: [])
        ctx.restoreGState()
    }

    /// White face element with very subtle inner bottom shadow (depth illusion)
    func face(path: CGPath) {
        ctx.saveGState()
        ctx.addPath(path); ctx.clip()
        ctx.setFillColor(white); ctx.fill(path.boundingBox)
        // Subtle bottom shadow inside
        let bb = path.boundingBox
        let inner = CGGradient(colorsSpace: cs, colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
            CGColor(srgbRed: 0.70, green: 0.65, blue: 0.88, alpha: 0.22),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(inner,
            start: CGPoint(x: bb.midX, y: bb.minY),
            end:   CGPoint(x: bb.midX, y: bb.maxY), options: [])
        ctx.restoreGState()
    }

    // ── 2. BACK FOLDER ─────────────────────────────────────────────
    // Slightly behind/above the front folder; tab protrudes at top-left
    let bW = s * 0.710      // width of back folder
    let bL = (s - bW) / 2  // left edge
    let bR = bL + bW
    let bBodyT = s * 0.218
    let bBodyB = s * 0.598
    let bTabTop = bBodyT - s * 0.078
    let bTabEnd = bL + bW * 0.375
    let bTabR = s * 0.032, bBodyR = s * 0.054
    let bBorder = s * 0.048

    let backPath = CGMutablePath()
    backPath.move(to: CGPoint(x: bL + bBodyR, y: bBodyB))
    backPath.addArc(tangent1End: CGPoint(x: bR,       y: bBodyB),
                    tangent2End: CGPoint(x: bR,       y: bBodyB - bBodyR), radius: bBodyR)
    backPath.addLine(to: CGPoint(x: bR, y: bBodyT + bBodyR))
    backPath.addArc(tangent1End: CGPoint(x: bR,       y: bBodyT),
                    tangent2End: CGPoint(x: bR - bBodyR, y: bBodyT), radius: bBodyR)
    backPath.addLine(to: CGPoint(x: bTabEnd, y: bBodyT))
    backPath.addLine(to: CGPoint(x: bTabEnd, y: bTabTop + bTabR))
    backPath.addArc(tangent1End: CGPoint(x: bTabEnd,       y: bTabTop),
                    tangent2End: CGPoint(x: bTabEnd - bTabR, y: bTabTop), radius: bTabR)
    backPath.addLine(to: CGPoint(x: bL + bTabR, y: bTabTop))
    backPath.addArc(tangent1End: CGPoint(x: bL, y: bTabTop),
                    tangent2End: CGPoint(x: bL, y: bTabTop + bTabR), radius: bTabR)
    backPath.addLine(to: CGPoint(x: bL, y: bBodyB - bBodyR))
    backPath.addArc(tangent1End: CGPoint(x: bL, y: bBodyB),
                    tangent2End: CGPoint(x: bL + bBodyR, y: bBodyB), radius: bBodyR)
    backPath.closeSubpath()

    sticker(path: backPath,
            c0: CGColor(srgbRed: 0.575, green: 0.540, blue: 0.910, alpha: 1),
            c1: CGColor(srgbRed: 0.485, green: 0.448, blue: 0.870, alpha: 1),
            from: CGPoint(x: bL, y: bTabTop),
            to:   CGPoint(x: bR, y: bBodyB),
            bw: bBorder)

    // White circle on the back folder tab (top-right of visible tab area)
    let tabDotR = s * 0.044
    let tabDotX = bTabEnd * 0.52 + bL * 0.48   // roughly center of tab
    let tabDotY = bTabTop + (bBodyT - bTabTop) * 0.50
    face(path: CGPath(ellipseIn: CGRect(
        x: tabDotX - tabDotR, y: tabDotY - tabDotR,
        width: tabDotR*2, height: tabDotR*2), transform: nil))

    // ── 3. FRONT FOLDER ────────────────────────────────────────────
    // Rounded rect, no tab — this is the "face" canvas
    let fW = s * 0.770
    let fL = (s - fW) / 2     // ~115
    let fR = fL + fW           // ~885
    let fT = s * 0.328
    let fB = s * 0.906
    let fCorner = s * 0.064
    let fBorder = s * 0.052

    let frontPath = CGPath(roundedRect:
        CGRect(x: fL, y: fT, width: fW, height: fB - fT),
        cornerWidth: fCorner, cornerHeight: fCorner, transform: nil)

    sticker(path: frontPath,
            c0: CGColor(srgbRed: 0.482, green: 0.438, blue: 0.868, alpha: 1),
            c1: CGColor(srgbRed: 0.388, green: 0.334, blue: 0.815, alpha: 1),
            from: CGPoint(x: fL, y: fT),
            to:   CGPoint(x: fR, y: fB),
            bw: fBorder)

    // ── 4. FACE ELEMENTS ───────────────────────────────────────────
    // All positioned relative to the front folder body

    let fw = fW                   // folder width
    let fh = fB - fT              // folder height

    // Eyes || — two vertical pills, upper-center of folder
    let eyeW = fw * 0.068
    let eyeH = fh * 0.235
    let eyeLX = fL + fw * 0.338   // left eye center x
    let eyeRX = fL + fw * 0.462   // right eye center x
    let eyeCY  = fT + fh * 0.430  // eye center y

    face(path: pill(cx: eyeLX, cy: eyeCY, w: eyeW, h: eyeH))
    face(path: pill(cx: eyeRX, cy: eyeCY, w: eyeW, h: eyeH))

    // Brow/dash — short horizontal pill, upper-right (like a raised eyebrow)
    let dashW = fw * 0.118, dashH = fh * 0.058
    let dashCX = fL + fw * 0.626
    let dashCY = fT + fh * 0.315
    face(path: pill(cx: dashCX, cy: dashCY, w: dashW, h: dashH))

    // Mouth — wide horizontal pill, lower portion of folder
    let mouthW = fw * 0.365, mouthH = fh * 0.078
    let mouthCX = fL + fw * 0.408
    let mouthCY = fT + fh * 0.728
    face(path: pill(cx: mouthCX, cy: mouthCY, w: mouthW, h: mouthH))

    // Ring ○ — right of mouth (annulus using even-odd fill)
    let ringOR = fw * 0.072    // outer radius
    let ringIR = fw * 0.038    // inner radius
    let ringCX = fL + fw * 0.640
    let ringCY = fT + fh * 0.732

    let annulus = CGMutablePath()
    annulus.addEllipse(in: CGRect(x: ringCX - ringOR, y: ringCY - ringOR,
                                   width: ringOR*2, height: ringOR*2))
    annulus.addEllipse(in: CGRect(x: ringCX - ringIR, y: ringCY - ringIR,
                                   width: ringIR*2, height: ringIR*2))

    // Draw with subtle inner bottom tint like other face elements
    ctx.saveGState()
    ctx.addPath(annulus)
    ctx.setFillColor(white)
    ctx.drawPath(using: .eoFill)
    // Add inner bottom shadow on the outer disk only
    ctx.addPath(annulus)
    ctx.clip(using: .evenOdd)
    let ringGrad = CGGradient(colorsSpace: cs, colors: [
        CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0),
        CGColor(srgbRed: 0.70, green: 0.65, blue: 0.88, alpha: 0.22),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(ringGrad,
        start: CGPoint(x: ringCX, y: ringCY - ringOR),
        end:   CGPoint(x: ringCX, y: ringCY + ringOR), options: [])
    ctx.restoreGState()

    // ── Done ───────────────────────────────────────────────────────
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!
}

// MARK: - Write all sizes and package into .icns

let sizes: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

print("Rendering sizes...")
var cache: [Int: Data] = [:]
for (name, px) in sizes {
    if cache[px] == nil { print("  \(px)px"); cache[px] = makeIcon(px: px) }
    try! cache[px]!.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name)"))
}

print("Packaging .icns...")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconsetPath, "-o", "AppIcon.icns"]
try! p.run(); p.waitUntilExit()
try? fm.removeItem(atPath: iconsetPath)
print(p.terminationStatus == 0 ? "✓ AppIcon.icns" : "✗ iconutil failed")
if p.terminationStatus != 0 { exit(1) }
