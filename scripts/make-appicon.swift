// Generates the PiDesktop app icon (macOS squircle + π + agent sparkle) at every
// required size, rendered natively with CoreGraphics — no third-party tools.
//
// Usage:
//   swift scripts/make-appicon.swift PiDesktop/Assets.xcassets/AppIcon.appiconset
//
// The icon follows macOS Big Sur+ conventions: the artwork is a squircle occupying
// 824/1024 of the canvas (the rest is shadow/margin), with a subtle drop shadow.

import Foundation
import CoreGraphics
import ImageIO

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
let S: CGFloat = 1024              // master canvas
let body: CGFloat = 824            // macOS icon body (rounded rect) within the canvas
let center = CGPoint(x: S / 2, y: S / 2)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: Int(S), height: Int(S),
                        bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}

// macOS Big Sur+ squircle: |x/a|^n + |y/a|^n = 1, n ≈ 5.
func squircle(half: CGFloat, n: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let steps = 1440
    let e = 2 / n
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let ct = cos(t), st = sin(t)
        let x = half * copysign(pow(abs(ct), e), ct)
        let y = half * copysign(pow(abs(st), e), st)
        let p = CGPoint(x: center.x + x, y: center.y + y)
        if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
    }
    path.closeSubpath()
    return path
}

context.setAllowsAntialiasing(true)
context.setShouldAntialias(true)
context.interpolationQuality = .high

let shape = squircle(half: body / 2)

// 1) Drop shadow + base fill.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -18), blur: 36,
                  color: color(0, 0, 0, 0.35))
context.addPath(shape)
context.setFillColor(color(0.36, 0.45, 0.98))
context.fillPath()
context.restoreGState()

// 2) Gradient body, clipped to the squircle.
context.saveGState()
context.addPath(shape)
context.clip()
let gradient = CGGradient(colorsSpace: space, colors: [
    color(0.42, 0.62, 1.00),   // top  #6B9EFF
    color(0.36, 0.45, 0.98),   // mid  #5C73FA
    color(0.55, 0.38, 0.96),   // bot  #8C61F5
] as CFArray, locations: [0.0, 0.5, 1.0])!
context.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0),
                           options: [])

// 3) Glass highlight (top sheen).
let sheen = CGGradient(colorsSpace: space, colors: [
    color(1, 1, 1, 0.40), color(1, 1, 1, 0.0),
] as CFArray, locations: [0.0, 1.0])!
context.drawLinearGradient(sheen,
                           start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: S * 0.45),
                           options: [])
context.restoreGState()

// 4) Rim highlight.
context.saveGState()
context.addPath(shape)
context.setStrokeColor(color(1, 1, 1, 0.25))
context.setLineWidth(6)
context.strokePath()
context.restoreGState()

// 5) π glyph (drawn as a path so it needs no font).
let piW: CGFloat = 360, piH: CGFloat = 300, legOff: CGFloat = 100, stroke: CGFloat = 74
let barY = center.y + piH / 2
let legBottom = center.y - piH / 2
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: color(0, 0, 0, 0.18))
context.setStrokeColor(color(1, 1, 1, 1))
context.setLineWidth(stroke)
context.setLineCap(.round)
context.setLineJoin(.round)
context.move(to: CGPoint(x: center.x - piW / 2, y: barY))
context.addLine(to: CGPoint(x: center.x + piW / 2, y: barY))
context.move(to: CGPoint(x: center.x - legOff, y: barY))
context.addLine(to: CGPoint(x: center.x - legOff, y: legBottom))
context.move(to: CGPoint(x: center.x + legOff, y: barY))
context.addLine(to: CGPoint(x: center.x + legOff, y: legBottom))
context.strokePath()
context.restoreGState()

// 6) Agent sparkle (four-point star) at the upper right.
func sparkle(at c: CGPoint, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let top = CGPoint(x: c.x, y: c.y + radius)
    let right = CGPoint(x: c.x + radius, y: c.y)
    let bottom = CGPoint(x: c.x, y: c.y - radius)
    let left = CGPoint(x: c.x - radius, y: c.y)
    path.move(to: top)
    path.addQuadCurve(to: right, control: c)
    path.addQuadCurve(to: bottom, control: c)
    path.addQuadCurve(to: left, control: c)
    path.addQuadCurve(to: top, control: c)
    path.closeSubpath()
    return path
}
context.saveGState()
context.addPath(sparkle(at: CGPoint(x: center.x + 252, y: center.y + 206), radius: 62))
context.setFillColor(color(1, 1, 1, 0.95))
context.fillPath()
context.addPath(sparkle(at: CGPoint(x: center.x + 306, y: center.y + 282), radius: 27))
context.setFillColor(color(1, 1, 1, 0.75))
context.fillPath()
context.restoreGState()

// Master image.
guard let master = context.makeImage() else { fatalError("render failed") }

// Downscale to each required slot.
func write(_ image: CGImage, pixels: Int, to name: String) {
    let ctx = CGContext(data: nil, width: pixels, height: pixels,
                        bitsPerComponent: 8, bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let out = ctx.makeImage()!
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(name) (\(pixels)px)")
}

let slots: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, px) in slots { write(master, pixels: px, to: name) }
