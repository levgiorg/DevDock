import AppKit

/// DevDock vector master; shared with docs/brand/midnight/devdock-mark.svg.
enum DevDockMark {
    static func paths() -> [NSBezierPath] {
        var paths: [NSBezierPath] = []
        do {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 48, y: 4))
            path.line(to: NSPoint(x: 75, y: 4))
            path.curve(to: NSPoint(x: 98, y: 28), controlPoint1: NSPoint(x: 91, y: 4), controlPoint2: NSPoint(x: 98, y: 13))
            path.line(to: NSPoint(x: 49, y: 28))
            path.curve(to: NSPoint(x: 24, y: 52), controlPoint1: NSPoint(x: 32, y: 28), controlPoint2: NSPoint(x: 24, y: 36))
            path.line(to: NSPoint(x: 24, y: 76))
            path.curve(to: NSPoint(x: 49, y: 100), controlPoint1: NSPoint(x: 24, y: 92), controlPoint2: NSPoint(x: 32, y: 100))
            path.line(to: NSPoint(x: 65, y: 100))
            path.curve(to: NSPoint(x: 75, y: 124), controlPoint1: NSPoint(x: 63, y: 109), controlPoint2: NSPoint(x: 67, y: 118))
            path.line(to: NSPoint(x: 47, y: 124))
            path.curve(to: NSPoint(x: 0, y: 78), controlPoint1: NSPoint(x: 17, y: 124), controlPoint2: NSPoint(x: 0, y: 108))
            path.line(to: NSPoint(x: 0, y: 50))
            path.curve(to: NSPoint(x: 48, y: 4), controlPoint1: NSPoint(x: 0, y: 20), controlPoint2: NSPoint(x: 17, y: 4))
            path.close()
            paths.append(path)
        }
        do {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 98, y: 4))
            path.line(to: NSPoint(x: 116, y: 4))
            path.curve(to: NSPoint(x: 164, y: 50), controlPoint1: NSPoint(x: 146, y: 4), controlPoint2: NSPoint(x: 164, y: 20))
            path.line(to: NSPoint(x: 164, y: 78))
            path.curve(to: NSPoint(x: 116, y: 124), controlPoint1: NSPoint(x: 164, y: 108), controlPoint2: NSPoint(x: 146, y: 124))
            path.line(to: NSPoint(x: 89, y: 124))
            path.curve(to: NSPoint(x: 66, y: 100), controlPoint1: NSPoint(x: 73, y: 124), controlPoint2: NSPoint(x: 66, y: 115))
            path.line(to: NSPoint(x: 115, y: 100))
            path.curve(to: NSPoint(x: 140, y: 76), controlPoint1: NSPoint(x: 132, y: 100), controlPoint2: NSPoint(x: 140, y: 92))
            path.line(to: NSPoint(x: 140, y: 52))
            path.curve(to: NSPoint(x: 115, y: 28), controlPoint1: NSPoint(x: 140, y: 36), controlPoint2: NSPoint(x: 132, y: 28))
            path.line(to: NSPoint(x: 109, y: 28))
            path.curve(to: NSPoint(x: 98, y: 4), controlPoint1: NSPoint(x: 111, y: 19), controlPoint2: NSPoint(x: 107, y: 10))
            path.close()
            paths.append(path)
        }
        return paths
    }

    static func draw(in rect: CGRect) {
        let transform = AffineTransform(m11: rect.width / 164, m12: 0, m21: 0, m22: rect.height / 128, tX: rect.minX, tY: rect.minY)
        for path in paths() { path.transform(using: transform); path.fill() }
    }
}
