import AppKit

let output = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        let shape = NSBezierPath(roundedRect: NSRect(x: 46, y: 46, width: 932, height: 932), xRadius: 210, yRadius: 210)
        NSGradient(starting: NSColor(calibratedWhite: 1, alpha: 1), ending: NSColor(calibratedWhite: 0.89, alpha: 1))!.draw(in: shape, angle: -90)
        let disc = NSBezierPath(ovalIn: NSRect(x: 144, y: 144, width: 736, height: 736))
        NSGradient(starting: NSColor(calibratedRed: 0.25, green: 0.91, blue: 0.58, alpha: 1), ending: NSColor(calibratedRed: 0.02, green: 0.50, blue: 0.47, alpha: 1))!.draw(in: disc, angle: -55)
        for diameter: CGFloat in [340, 550] {
            let ring = NSBezierPath(ovalIn: NSRect(x: 512-diameter/2, y: 512-diameter/2, width: diameter, height: diameter))
            NSColor.white.withAlphaComponent(0.23).setStroke()
            ring.lineWidth = 12
            ring.stroke()
        }
        // A broken orbit and directional arrow distinguish this from Find My's radar.
        let orbit = NSBezierPath()
        orbit.appendArc(withCenter: NSPoint(x: 512, y: 512), radius: 260, startAngle: 100, endAngle: 345, clockwise: false)
        orbit.lineWidth = 44
        orbit.lineCapStyle = .round
        NSColor.white.withAlphaComponent(0.92).setStroke()
        orbit.stroke()
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: 786, y: 804))
        arrow.line(to: NSPoint(x: 680, y: 440))
        arrow.curve(to: NSPoint(x: 647, y: 438), controlPoint1: NSPoint(x: 674, y: 420), controlPoint2: NSPoint(x: 654, y: 420))
        arrow.line(to: NSPoint(x: 574, y: 582))
        arrow.line(to: NSPoint(x: 430, y: 652))
        arrow.curve(to: NSPoint(x: 432, y: 686), controlPoint1: NSPoint(x: 410, y: 660), controlPoint2: NSPoint(x: 413, y: 680))
        arrow.close()
        NSColor(calibratedRed: 0.22, green: 0.27, blue: 0.88, alpha: 1).setFill()
        arrow.fill()
        NSColor.white.withAlphaComponent(0.96).setStroke()
        arrow.lineWidth = 16
        arrow.lineJoinStyle = .round
        arrow.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/icon_\(size)x\(size)\(suffix).png"))
    }
}
