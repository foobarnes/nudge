import AppKit

extension NSImage {
    /// Nudge's menu bar glyph: a branch whose head is a solid clock with cut-out hands. Drawn on an 18-pt grid as a
    /// template image, so the hands are true transparency and it tints with the menu bar. Stale dims it.
    static func nudgeGlyph(stale: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            // One transparency layer so overlapping strokes dim evenly instead of stacking up darker.
            guard let cg = NSGraphicsContext.current?.cgContext else { return false }
            cg.setAlpha(stale ? 0.45 : 1)
            cg.beginTransparencyLayer(auxiliaryInfo: nil)
            defer { cg.endTransparencyLayer() }
            NSColor.black.set()

            let trunk = NSBezierPath()
            trunk.move(to: NSPoint(x: 4.5, y: 5.3))
            trunk.line(to: NSPoint(x: 4.5, y: 12.7))
            trunk.lineWidth = 1.6
            trunk.lineCapStyle = .round
            trunk.stroke()

            for y in [3.6, 14.4] {
                let node = NSBezierPath(ovalIn: NSRect(x: 4.5 - 1.7, y: y - 1.7, width: 3.4, height: 3.4))
                node.lineWidth = 1.4
                node.stroke()
            }

            let branch = NSBezierPath()
            branch.move(to: NSPoint(x: 12.4, y: 10.8))
            branch.line(to: NSPoint(x: 12.4, y: 11.4))
            branch.appendArc(withCenter: NSPoint(x: 9.6, y: 11.4), radius: 2.8, startAngle: 0, endAngle: 90, clockwise: false)
            branch.line(to: NSPoint(x: 6.4, y: 14.2))
            branch.lineWidth = 1.6
            branch.lineCapStyle = .round
            branch.lineJoinStyle = .round
            branch.stroke()

            NSBezierPath(ovalIn: NSRect(x: 12.4 - 4.6, y: 6.2 - 4.6, width: 9.2, height: 9.2)).fill()

            NSGraphicsContext.current?.compositingOperation = .destinationOut
            let hands = NSBezierPath()
            hands.move(to: NSPoint(x: 12.4, y: 3.4))
            hands.line(to: NSPoint(x: 12.4, y: 6.2))
            hands.line(to: NSPoint(x: 14.6, y: 7.4))
            hands.lineWidth = 1.3
            hands.lineCapStyle = .round
            hands.lineJoinStyle = .round
            hands.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
