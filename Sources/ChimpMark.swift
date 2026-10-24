import AppKit

/// The canonical Chimprace face and an overlaid stopwatch, drawn as native vectors.
/// drawing; the flat glyph has transparent cutouts and can be a template image.
enum ChimpMark {
    static func image(size: CGFloat = 24, resting: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            draw(in: rect, color: .black, resting: resting)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = resting ? "Chimpodoro, resting" : "Chimpodoro"
        return image
    }

    static func draw(in rect: NSRect, color: NSColor, resting: Bool = false) {
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let side = min(rect.width, rect.height)
        let transform = NSAffineTransform()
        transform.translateX(by: rect.midX - side / 2, yBy: rect.midY - side / 2)
        transform.scale(by: side / 100)
        transform.concat()
        color.setFill()
        color.setStroke()

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        defer { context.endTransparencyLayer() }

        // Exact geometry from Chimprace client/index.html #chimp and iOS
        // LogoView.swift: 32-unit SVG coordinates, uniformly scaled and flipped.
        func ellipse(_ x: CGFloat, _ y: CGFloat, _ rx: CGFloat, _ ry: CGFloat) -> CGRect {
            CGRect(x: (x-rx)*100/32, y: (32-y-ry)*100/32,
                   width: rx*200/32, height: ry*200/32)
        }
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: ellipse(7, 12, 4.5, 4.5))
        context.fillEllipse(in: ellipse(25, 12, 4.5, 4.5))
        context.fillEllipse(in: ellipse(16, 14, 9, 9))
        context.setBlendMode(.clear)
        context.fillEllipse(in: ellipse(16, 19, 6.5, 5))
        if resting {
            for x in [CGFloat(12.5), CGFloat(19.5)] {
                context.move(to: CGPoint(x: (x-1.4)*100/32, y: 19.5*100/32))
                context.addQuadCurve(to: CGPoint(x: (x+1.4)*100/32, y: 19.5*100/32),
                                     control: CGPoint(x: x*100/32, y: 18.2*100/32))
                context.setLineWidth(0.8*100/32); context.setLineCap(.round); context.strokePath()
            }
        } else {
            context.fillEllipse(in: ellipse(12.5, 12.5, 1.4, 1.4))
            context.fillEllipse(in: ellipse(19.5, 12.5, 1.4, 1.4))
        }
        context.setBlendMode(.normal)
        context.setStrokeColor(color.cgColor)
        context.move(to: CGPoint(x: 13*100/32, y: 11.5*100/32))
        context.addQuadCurve(to: CGPoint(x: 19*100/32, y: 11.5*100/32),
                             control: CGPoint(x: 16*100/32, y: 9.1*100/32))
        context.setLineWidth(1.3*100/32); context.setLineCap(.round); context.strokePath()

        // Stopwatch badge overlaps the lower-right ear/head. A transparent
        // knockout separates the badge from the face on any appearance.
        context.setBlendMode(.clear)
        context.fillEllipse(in: CGRect(x: 60, y: 7, width: 40, height: 40))
        context.fillEllipse(in: CGRect(x: 71, y: 40, width: 18, height: 12))
        context.setBlendMode(.normal)
        context.setStrokeColor(color.cgColor); context.setFillColor(color.cgColor)
        context.setLineWidth(4)
        context.strokeEllipse(in: CGRect(x: 65, y: 12, width: 30, height: 30))
        NSBezierPath(roundedRect: NSRect(x: 75, y: 45, width: 10, height: 4), xRadius: 1, yRadius: 1).fill()
        context.move(to: CGPoint(x: 80, y: 36))
        context.addLine(to: CGPoint(x: 80, y: 27))
        context.addLine(to: CGPoint(x: 87, y: 23))
        context.setLineWidth(3); context.setLineCap(.round); context.setLineJoin(.round); context.strokePath()
    }

    static func drawAppIcon(in rect: NSRect) {
        let side = min(rect.width, rect.height)
        let square = NSRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
        let tile = square.insetBy(dx: side * 0.055, dy: side * 0.055)
        NSColor(srgbRed: 0.055, green: 0.055, blue: 0.055, alpha: 1).setFill()
        NSBezierPath(roundedRect: tile, xRadius: side * 0.19, yRadius: side * 0.19).fill()
        draw(in: square.insetBy(dx: side * 0.12, dy: side * 0.12), color: .white)

        // App-icon-only tomato: the shared glyph and menu bar stay unchanged.
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let transform = NSAffineTransform()
        transform.translateX(by: square.minX, yBy: square.minY)
        transform.scale(by: side / 100); transform.concat()
        let tomato = NSBezierPath()
        tomato.move(to: NSPoint(x: 28, y: 38))
        tomato.curve(to: NSPoint(x: 16, y: 32), controlPoint1: NSPoint(x: 20, y: 42), controlPoint2: NSPoint(x: 15, y: 37))
        tomato.curve(to: NSPoint(x: 28, y: 21), controlPoint1: NSPoint(x: 15, y: 25), controlPoint2: NSPoint(x: 21, y: 20))
        tomato.curve(to: NSPoint(x: 40, y: 32), controlPoint1: NSPoint(x: 35, y: 20), controlPoint2: NSPoint(x: 41, y: 25))
        tomato.curve(to: NSPoint(x: 28, y: 38), controlPoint1: NSPoint(x: 41, y: 37), controlPoint2: NSPoint(x: 36, y: 42))
        tomato.close()
        NSColor(srgbRed: 0.86, green: 0.28, blue: 0.23, alpha: 1).setFill(); tomato.fill()
        let leaves = NSBezierPath()
        leaves.move(to: NSPoint(x: 28, y: 38))
        for point in [NSPoint(x: 21, y: 41), NSPoint(x: 25, y: 36),
                      NSPoint(x: 23, y: 33), NSPoint(x: 28, y: 35),
                      NSPoint(x: 33, y: 33), NSPoint(x: 31, y: 37),
                      NSPoint(x: 35, y: 41), NSPoint(x: 29, y: 39)] { leaves.line(to: point) }
        leaves.close()
        NSColor(srgbRed: 0.42, green: 0.59, blue: 0.37, alpha: 1).setFill(); leaves.fill()
        let stem = NSBezierPath()
        stem.move(to: NSPoint(x: 28, y: 38)); stem.curve(to: NSPoint(x: 30, y: 44), controlPoint1: NSPoint(x: 27, y: 41), controlPoint2: NSPoint(x: 28, y: 43))
        NSColor(srgbRed: 0.42, green: 0.59, blue: 0.37, alpha: 1).setStroke()
        stem.lineWidth = 1.7; stem.lineCapStyle = .round; stem.stroke()

    }
}
