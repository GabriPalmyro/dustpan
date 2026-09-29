// Draws the Dustpan app icon (a 2D broom sweeping "electronic dust") and writes Resources/AppIcon.icns.
//   swift scripts/make-icon.swift
import AppKit

let size: CGFloat = 1024

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func draw(_ ctx: CGContext) {
    // Squircle tile (macOS icon grid: 824pt tile inside 1024 canvas).
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: color(0x6B4A3A, 0.18))
    ctx.addPath(tilePath); ctx.setFillColor(color(0xF8E6D8)); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    // Warm white fading into a soft skin tone.
    linear(ctx, [color(0xFFFCF8), color(0xF7E3D3), color(0xF0CDB7)],
           from: CGPoint(x: 400, y: 924), to: CGPoint(x: 624, y: 100))

    // Electronic dust: flat pixels trailing away from the bristles, fading with distance.
    let dust: [(x: CGFloat, y: CGFloat, s: CGFloat, c: UInt32, a: CGFloat)] = [
        (318, 318, 46, 0x7FC8B4, 1.0),
        (248, 392, 34, 0xA3A9EE, 1.0),
        (372, 236, 30, 0xA3A9EE, 0.9),
        (232, 290, 26, 0x7FC8B4, 0.85),
        (300, 470, 22, 0x7FC8B4, 0.7),
        (190, 440, 18, 0xA3A9EE, 0.6),
        (186, 350, 14, 0x7FC8B4, 0.5),
        (250, 540, 14, 0xA3A9EE, 0.45),
        (440, 190, 16, 0x7FC8B4, 0.6),
    ]
    for d in dust {
        let r = CGRect(x: d.x - d.s / 2, y: d.y - d.s / 2, width: d.s, height: d.s)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: d.s * 0.18, cornerHeight: d.s * 0.18, transform: nil))
        ctx.setFillColor(color(d.c, d.a)); ctx.fillPath()
    }

    // Broom — flat, three solid shapes, drawn upright then tilted so the handle points up-right.
    let ink = color(0x4A3B38)
    let bristleColor = color(0xE3927A)
    let paper = color(0xF7E3D3)

    ctx.saveGState()
    ctx.translateBy(x: 575, y: 480)
    ctx.rotate(by: -.pi / 5.2)

    // Handle.
    ctx.addPath(CGPath(roundedRect: CGRect(x: -17, y: 48, width: 34, height: 380), cornerWidth: 17, cornerHeight: 17, transform: nil))
    ctx.setFillColor(ink); ctx.fillPath()

    // Bristles.
    let bristles = CGMutablePath()
    bristles.move(to: CGPoint(x: -62, y: 6))
    bristles.addLine(to: CGPoint(x: 62, y: 6))
    bristles.addLine(to: CGPoint(x: 138, y: -240))
    bristles.addQuadCurve(to: CGPoint(x: -138, y: -240), control: CGPoint(x: 0, y: -262))
    bristles.closeSubpath()
    ctx.addPath(bristles); ctx.setFillColor(bristleColor); ctx.fillPath()

    // Negative-space slits between bristle bundles.
    ctx.saveGState()
    ctx.addPath(bristles); ctx.clip()
    ctx.setStrokeColor(paper); ctx.setLineWidth(12); ctx.setLineCap(.round)
    for t in [-0.5, 0.0, 0.5] as [CGFloat] {
        ctx.move(to: CGPoint(x: t * 70, y: -70))
        ctx.addLine(to: CGPoint(x: t * 150, y: -290))
    }
    ctx.strokePath()
    ctx.restoreGState()

    // Binding band.
    ctx.addPath(CGPath(roundedRect: CGRect(x: -74, y: -2, width: 148, height: 56), cornerWidth: 18, cornerHeight: 18, transform: nil))
    ctx.setFillColor(ink); ctx.fillPath()
    ctx.restoreGState()

    ctx.restoreGState()
}

func png(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!.cgContext
    ctx.scaleBy(x: CGFloat(px) / size, y: CGFloat(px) / size)
    draw(ctx)
    return rep.representation(using: .png, properties: [:])!
}

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try png(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try png(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let resources = root.appendingPathComponent("Resources")
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try png(1024).write(to: resources.appendingPathComponent("AppIcon.png"))

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path]
try iconutil.run(); iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote Resources/AppIcon.icns" : "iconutil failed")
