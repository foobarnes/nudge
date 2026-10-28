// Renders the README banner (light and dark) and hero image.
// Usage: swift .github/assets/render.swift <Nudge.app> <pill-window.png> <out-dir>
import AppKit

let args = CommandLine.arguments
let app = args[1], pillPath = args[2], outDir = args[3]
let icon = NSWorkspace.shared.icon(forFile: app)
let pill = NSImage(contentsOfFile: pillPath)!

func hex(_ v: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat(v >> 16 & 0xFF) / 255, green: CGFloat(v >> 8 & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: a)
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded)!, size: size)!
}

func render(_ name: String, width: CGFloat, height: CGFloat, draw: (NSRect) -> Void) {
    let scale: CGFloat = 2
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    draw(NSRect(x: 0, y: 0, width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(outDir)/\(name).png"))
}

func glow(_ center: NSPoint, _ radius: CGFloat, _ color: NSColor) {
    let g = NSGradient(colors: [color, color.withAlphaComponent(0)])!
    g.draw(fromCenter: center, radius: 0, toCenter: center, radius: radius, options: [])
}

func roundedBackground(_ r: NSRect, _ fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: r, xRadius: 36, yRadius: 36).fill()
}

for dark in [false, true] {
    render(dark ? "banner-dark" : "banner-light", width: 1280, height: 400) { r in
        NSBezierPath(roundedRect: r, xRadius: 36, yRadius: 36).addClip()
        (dark ? hex(0x120D2A) : hex(0xF8F6FF)).setFill(); r.fill()
        glow(NSPoint(x: 220, y: 60), 520, dark ? hex(0x7457FF, 0.35) : hex(0x7457FF, 0.16))
        glow(NSPoint(x: 1160, y: 380), 480, dark ? hex(0x2A1A8A, 0.7) : hex(0xC9BCFF, 0.45))
        icon.draw(in: NSRect(x: 150, y: 70, width: 260, height: 260))
        let ink = dark ? hex(0xF3F0FF) : hex(0x241A6B)
        let sub = dark ? hex(0xB9B2DC) : hex(0x4B3F8F)
        ("nudge" as NSString).draw(at: NSPoint(x: 450, y: 170), withAttributes: [.font: rounded(132, .black), .foregroundColor: ink, .kern: -4])
        ("The reviews waiting on you, and for how long." as NSString)
            .draw(at: NSPoint(x: 458, y: 112), withAttributes: [.font: rounded(34, .semibold), .foregroundColor: sub])
    }
}

render("hero", width: 1280, height: 760) { r in
    NSBezierPath(roundedRect: r, xRadius: 36, yRadius: 36).addClip()
    let bg = NSGradient(colors: [hex(0x7457FF), hex(0x2A1A8A)])!
    bg.draw(in: r, angle: -90)
    glow(NSPoint(x: 160, y: 80), 560, hex(0xFF9F6E, 0.45))
    glow(NSPoint(x: 1180, y: 700), 520, hex(0xB7A8FF, 0.45))
    // A slim menu bar so the pill reads as living on the desktop.
    hex(0xFFFFFF, 0.16).setFill(); NSRect(x: 0, y: r.maxY - 34, width: r.width, height: 34).fill()
    let bar: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 15, weight: .semibold), .foregroundColor: NSColor.white]
    ("Wed Oct 28  2:14 PM" as NSString).draw(at: NSPoint(x: r.maxX - 190, y: r.maxY - 26), withAttributes: bar)
    let w: CGFloat = 448 * 1.25, h = w * pill.size.height / pill.size.width
    let frame = NSRect(x: r.midX - w / 2, y: (r.height - 34 - h) / 2, width: w, height: h)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowBlurRadius = 50
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.set()
    pill.draw(in: frame)
}
