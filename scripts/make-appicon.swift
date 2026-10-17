// Generates the PiDesktop app icons (macOS squircle + π + agent sparkle) at every
// required size, rendered natively with CoreGraphics / CoreText — no third-party tools.
//
// Usage:
//   swift scripts/make-appicon.swift PiDesktop/Assets.xcassets
//
// The argument may be the `Assets.xcassets` folder (recommended) or the existing
// `AppIcon.appiconset` folder; both write next to each other.
//
// Outputs:
//   AppIcon.appiconset      — production icon (all 10 macOS slots)
//   AppIconDev.imageset     — DEBUG-only icon with a large semi-transparent
//                             "测" capsule in the bottom-right corner (256pt
//                             @1x/@2x, enough for the Dock; AppDelegate swaps
//                             it in at launch in DEBUG)
//
// The icon follows macOS Big Sur+ conventions: the artwork is a squircle occupying
// 824/1024 of the canvas (the rest is shadow/margin), with a subtle drop shadow.

import AppKit
import CoreGraphics
import CoreText
import Foundation
import ImageIO

// MARK: - Canvas

let S: CGFloat = 1024              // master canvas
let body: CGFloat = 824            // macOS icon body (rounded rect) within the canvas
let center = CGPoint(x: S / 2, y: S / 2)
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func makeContext() -> CGContext {
    CGContext(
        data: nil, width: Int(S), height: Int(S),
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
}

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

// Agent sparkle (four-point star).
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

// MARK: - Production icon

func drawBaseIcon(in context: CGContext) {
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.interpolationQuality = .high

    let shape = squircle(half: body / 2)

    // 1) Drop shadow + base fill.
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -18), blur: 36,
        color: color(0, 0, 0, 0.35)
    )
    context.addPath(shape)
    context.setFillColor(color(0.36, 0.45, 0.98))
    context.fillPath()
    context.restoreGState()

    // 2) Gradient body, clipped to the squircle.
    context.saveGState()
    context.addPath(shape)
    context.clip()
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [
            color(0.42, 0.62, 1.00),   // top  #6B9EFF
            color(0.36, 0.45, 0.98),   // mid  #5C73FA
            color(0.55, 0.38, 0.96),   // bot  #8C61F5
        ] as CFArray,
        locations: [0.0, 0.5, 1.0]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: S), end: CGPoint(x: S, y: 0),
        options: []
    )

    // 3) Glass highlight (top sheen).
    let sheen = CGGradient(
        colorsSpace: space,
        colors: [
            color(1, 1, 1, 0.40), color(1, 1, 1, 0.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    context.drawLinearGradient(
        sheen,
        start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: S * 0.45),
        options: []
    )
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

    // 6) Agent sparkle at the upper right.
    context.saveGState()
    context.addPath(sparkle(at: CGPoint(x: center.x + 252, y: center.y + 206), radius: 62))
    context.setFillColor(color(1, 1, 1, 0.95))
    context.fillPath()
    context.addPath(sparkle(at: CGPoint(x: center.x + 306, y: center.y + 282), radius: 27))
    context.setFillColor(color(1, 1, 1, 0.75))
    context.fillPath()
    context.restoreGState()
}

// MARK: - Test-build icon

/// Draws a large semi-transparent "测" capsule in the bottom-right corner.
///
/// The capsule is only used by the DEBUG build (`AppDelegate` swaps the Dock
/// icon), so the production icon never carries it. It deliberately sits low
/// enough to clear the π glyph and stays inside the squircle.
func drawTestBadge(in context: CGContext) {
    // 一枚半透明胶囊，沿用 MomentumMacOS 测试版标签的视觉语言（深色半透明底 +
    // 白色粗体字），但位置移到右下角，内容换成一个尽量大的「测」。
    let badgeSize = CGSize(width: 300, height: 260)
    let badgeCenter = CGPoint(x: center.x + 178, y: center.y - 260)
    let cornerRadius: CGFloat = badgeSize.height / 2
    let badgeRect = CGRect(
        x: badgeCenter.x - badgeSize.width / 2,
        y: badgeCenter.y - badgeSize.height / 2,
        width: badgeSize.width,
        height: badgeSize.height
    )
    let badgePath = CGPath(
        roundedRect: badgeRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )

    // 半透明深色底：让底图的蓝紫渐变透出来，而不是盖成一块实色。
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: color(0, 0, 0, 0.30))
    context.addPath(badgePath)
    context.setFillColor(color(0.08, 0.07, 0.16, 0.55))
    context.fillPath()
    context.restoreGState()

    // 顶部高光，模拟玻璃质感。
    context.saveGState()
    context.addPath(badgePath)
    context.clip()
    let sheen = CGGradient(
        colorsSpace: space,
        colors: [
            color(1, 1, 1, 0.16),
            color(1, 1, 1, 0.0),
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    context.drawLinearGradient(
        sheen,
        start: CGPoint(x: 0, y: badgeRect.maxY),
        end: CGPoint(x: 0, y: badgeRect.midY),
        options: []
    )
    context.restoreGState()

    // 细白边，保证在深浅底图上都有清晰轮廓。
    let rimRect = badgeRect.insetBy(dx: 4, dy: 4)
    let rimPath = CGPath(
        roundedRect: rimRect,
        cornerWidth: cornerRadius - 4,
        cornerHeight: cornerRadius - 4,
        transform: nil
    )
    context.saveGState()
    context.addPath(rimPath)
    context.setStrokeColor(color(1, 1, 1, 0.32))
    context.setLineWidth(6)
    context.strokePath()
    context.restoreGState()

    // 「测」——大号白字，尽量占满胶囊高度。
    context.saveGState()
    let font = CTFontCreateWithName("PingFangSC-Semibold" as CFString, 180, nil)
    let attributes: [NSAttributedString.Key: Any] = [
        kCTFontAttributeName as NSAttributedString.Key: font,
        kCTForegroundColorAttributeName as NSAttributedString.Key: color(1, 1, 1, 0.96),
    ]
    let line = CTLineCreateWithAttributedString(
        NSAttributedString(string: "测", attributes: attributes)
    )
    let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
    context.textPosition = CGPoint(
        x: badgeCenter.x - bounds.width / 2 - bounds.minX,
        y: badgeCenter.y - bounds.height / 2 - bounds.minY
    )
    context.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: color(0, 0, 0, 0.30))
    CTLineDraw(line, context)
    context.restoreGState()
}

func makeMaster(withTestBadge: Bool) -> CGImage {
    let context = makeContext()
    drawBaseIcon(in: context)
    if withTestBadge { drawTestBadge(in: context) }
    guard let image = context.makeImage() else { fatalError("render failed") }
    return image
}

// MARK: - Output

let defaultPath = "PiDesktop/Assets.xcassets"
let argument = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultPath
let inputURL = URL(fileURLWithPath: argument)

// Accept either `.../Assets.xcassets` or the older `.../AppIcon.appiconset`.
let assetsRoot: URL
if inputURL.lastPathComponent == "AppIcon.appiconset" {
    assetsRoot = inputURL.deletingLastPathComponent()
} else {
    assetsRoot = inputURL
}
let appIconDir = assetsRoot.appendingPathComponent("AppIcon.appiconset", isDirectory: true)
let testIconDir = assetsRoot.appendingPathComponent("AppIconDev.imageset", isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: appIconDir, withIntermediateDirectories: true)
try fileManager.createDirectory(at: testIconDir, withIntermediateDirectories: true)

func write(_ image: CGImage, pixels: Int, to name: String, in directory: URL) {
    let ctx = CGContext(
        data: nil, width: pixels, height: pixels,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    ctx.interpolationQuality = .high
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let out = ctx.makeImage()!
    let url = directory.appendingPathComponent(name)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, out, nil)
    CGImageDestinationFinalize(dest)
    print("wrote \(url.lastPathComponent) (\(pixels)px) → \(directory.lastPathComponent)")
}

let appIconSlots: [(String, Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
let productionMaster = makeMaster(withTestBadge: false)
for (name, px) in appIconSlots {
    write(productionMaster, pixels: px, to: name, in: appIconDir)
}

// The Dock never needs more than 128pt (@2x = 256px); 256pt covers every case
// without bloating Assets.car in the release build.
let testIconSlots: [(String, Int)] = [
    ("AppIconDev.png", 256), ("AppIconDev@2x.png", 512),
]
let testMaster = makeMaster(withTestBadge: true)
for (name, px) in testIconSlots {
    write(testMaster, pixels: px, to: name, in: testIconDir)
}

// Keep the asset catalog metadata in sync with the files above.
let appIconContents = """
{
  "images" : [
    {
      "filename" : "icon_16x16.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_16x16@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "16x16"
    },
    {
      "filename" : "icon_32x32.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_32x32@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "32x32"
    },
    {
      "filename" : "icon_128x128.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_128x128@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "128x128"
    },
    {
      "filename" : "icon_256x256.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_256x256@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    },
    {
      "filename" : "icon_512x512.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "512x512"
    },
    {
      "filename" : "icon_512x512@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "512x512"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
let testIconContents = """
{
  "images" : [
    {
      "filename" : "AppIconDev.png",
      "idiom" : "mac",
      "scale" : "1x",
      "size" : "256x256"
    },
    {
      "filename" : "AppIconDev@2x.png",
      "idiom" : "mac",
      "scale" : "2x",
      "size" : "256x256"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}

"""
try appIconContents.write(
    to: appIconDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8
)
try testIconContents.write(
    to: testIconDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8
)
print("✓ AppIcon.appiconset (production)")
print("✓ AppIconDev.imageset (DEBUG, translucent “测” capsule)")
