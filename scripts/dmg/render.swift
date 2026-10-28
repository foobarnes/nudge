// Renders the committed DMG assets: background.png, background@2x.png and the fallback VolumeIcon.icns.
// Regenerate with: swift scripts/dmg/render.swift   (run from the repo root, or pass the output directory)
//
// The layout constants mirror scripts/dmg/settings.py: a 660×400 pt content area with 128 pt icons centred at
// (180, 176) and (480, 176), measured from the content's top-left like Finder does.

import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "scripts/dmg")
let size = CGSize(width: 660, height: 400)
let iconY: CGFloat = 176
let appX: CGFloat = 180, applicationsX: CGFloat = 480

func rgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}
let violet: UInt32 = 0x7457FF, indigo: UInt32 = 0x2A1A8A, paper: UInt32 = 0xF8F6FF

func roundedFont(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

/// Draws in Finder's coordinate space: points, origin top-left.
func drawBackground(_ ctx: CGContext) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Paper, warming very slightly toward lavender at the bottom.
    ctx.drawLinearGradient(
        CGGradient(colorsSpace: space, colors: [rgb(paper), rgb(0xEEEAFF)] as CFArray, locations: [0, 1])!,
        start: .zero, end: CGPoint(x: 0, y: size.height), options: [])

    // Two soft violet glows: one behind the app, a fainter one behind Applications.
    for (x, alpha, radius) in [(appX, 0.16, 210.0), (applicationsX, 0.09, 190.0)] {
        let center = CGPoint(x: x, y: iconY)
        ctx.drawRadialGradient(
            CGGradient(colorsSpace: space, colors: [rgb(violet, alpha), rgb(violet, 0)] as CFArray,
                       locations: [0, 1])!,
            startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
    }

    // The cue: a trail of dots that firm up as they travel right, ending in a rounded chevron.
    let startX: CGFloat = 278, endX: CGFloat = 358, dots = 5
    for i in 0..<dots {
        let t = CGFloat(i) / CGFloat(dots - 1)
        let r = 3 + 1.5 * t
        ctx.setFillColor(rgb(violet, 0.25 + 0.6 * t))
        ctx.fillEllipse(in: CGRect(x: startX + (endX - startX) * t - r, y: iconY - r, width: 2 * r, height: 2 * r))
    }
    ctx.setStrokeColor(rgb(violet))
    ctx.setLineWidth(6)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.move(to: CGPoint(x: 369, y: iconY - 15))
    ctx.addLine(to: CGPoint(x: 384, y: iconY))
    ctx.addLine(to: CGPoint(x: 369, y: iconY + 15))
    ctx.strokePath()

    // Caption: "Drag nudge to Applications", with the wordmark set in heavy rounded violet.
    let body = roundedFont(15, .semibold), mark = roundedFont(17, .black)
    let caption = NSMutableAttributedString()
    caption.append(NSAttributedString(string: "Drag ", attributes: [.font: body, .foregroundColor: NSColor(cgColor: rgb(indigo, 0.62))!]))
    caption.append(NSAttributedString(string: "nudge", attributes: [.font: mark, .foregroundColor: NSColor(cgColor: rgb(violet))!]))
    caption.append(NSAttributedString(string: " to Applications", attributes: [.font: body, .foregroundColor: NSColor(cgColor: rgb(indigo, 0.62))!]))
    let textSize = caption.size()
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
    caption.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: 316))
    NSGraphicsContext.restoreGraphicsState()
}

func renderPNG(scale: CGFloat, to url: URL) throws {
    let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                        bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: size.height * scale)
    ctx.scaleBy(x: scale, y: -scale)
    drawBackground(ctx)
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    rep.size = size  // 72 dpi at 1x, 144 dpi at 2x, so tiffutil pairs them as one HiDPI image
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}

/// Fallback volume icon, rendered from the flat brand SVG, for builds whose app has no AppIcon.icns.
func renderVolumeIcon(to url: URL) throws {
    guard let svg = NSImage(contentsOf: outDir.appendingPathComponent("icon-flat.svg")) else {
        throw NSError(domain: "render", code: 1, userInfo: [NSLocalizedDescriptionKey: "can't read icon-flat.svg"])
    }
    let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("VolumeIcon.iconset")
    try? FileManager.default.removeItem(at: iconset)
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let px = points * scale
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            svg.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
            NSGraphicsContext.restoreGraphicsState()
            let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
            try rep.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent(name))
        }
    }
    let iconutil = Process()
    iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    iconutil.arguments = ["-c", "icns", iconset.path, "-o", url.path]
    try iconutil.run()
    iconutil.waitUntilExit()
    guard iconutil.terminationStatus == 0 else {
        throw NSError(domain: "render", code: 2, userInfo: [NSLocalizedDescriptionKey: "iconutil failed"])
    }
}

try renderPNG(scale: 1, to: outDir.appendingPathComponent("background.png"))
try renderPNG(scale: 2, to: outDir.appendingPathComponent("background@2x.png"))
try renderVolumeIcon(to: outDir.appendingPathComponent("VolumeIcon.icns"))
print("Wrote background.png, background@2x.png and VolumeIcon.icns to \(outDir.path)")
