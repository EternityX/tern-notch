import AppKit

func draw(_ size: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = size / 1024
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let tilePath = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(colors: [NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.22, alpha: 1),
                        NSColor(calibratedRed: 0.04, green: 0.05, blue: 0.08, alpha: 1)])!
        .draw(in: tilePath, angle: -90)
    NSColor.white.withAlphaComponent(0.08).setStroke()
    tilePath.lineWidth = 4 * s
    tilePath.stroke()

    let notchWidth = 520 * s, notchHeight = 250 * s, radius = 80 * s, ear = 34 * s
    let left = (size - notchWidth) / 2, top = tile.maxY, bottom = top - notchHeight
    let notch = NSBezierPath()
    notch.move(to: NSPoint(x: left - ear, y: top))
    notch.curve(to: NSPoint(x: left, y: top - ear), controlPoint1: NSPoint(x: left, y: top), controlPoint2: NSPoint(x: left, y: top))
    notch.line(to: NSPoint(x: left, y: bottom + radius))
    notch.curve(to: NSPoint(x: left + radius, y: bottom), controlPoint1: NSPoint(x: left, y: bottom), controlPoint2: NSPoint(x: left, y: bottom))
    notch.line(to: NSPoint(x: left + notchWidth - radius, y: bottom))
    notch.curve(to: NSPoint(x: left + notchWidth, y: bottom + radius), controlPoint1: NSPoint(x: left + notchWidth, y: bottom), controlPoint2: NSPoint(x: left + notchWidth, y: bottom))
    notch.line(to: NSPoint(x: left + notchWidth, y: top - ear))
    notch.curve(to: NSPoint(x: left + notchWidth + ear, y: top), controlPoint1: NSPoint(x: left + notchWidth, y: top), controlPoint2: NSPoint(x: left + notchWidth, y: top))
    notch.close()
    NSGraphicsContext.current?.saveGraphicsState()
    tilePath.addClip()
    NSColor.black.setFill()
    notch.fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    let blue = NSColor(calibratedRed: 0.38, green: 0.66, blue: 1.0, alpha: 1)
    let barWidth = 30 * s, gap = 24 * s
    let heights: [CGFloat] = [70, 130, 105, 60].map { $0 * s }
    let centerY = bottom + notchHeight * 0.42
    var x = left + 70 * s
    for h in heights {
        blue.setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: centerY - h / 2, width: barWidth, height: h), xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        x += barWidth + gap
    }

    let orange = NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)
    let dot = NSRect(x: left + notchWidth - 135 * s, y: centerY - 34 * s, width: 68 * s, height: 68 * s)
    let glow = NSShadow()
    glow.shadowColor = orange.withAlphaComponent(0.9)
    glow.shadowBlurRadius = 40 * s
    glow.set()
    orange.setFill()
    NSBezierPath(ovalIn: dot).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let dir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let data = draw(CGFloat(px)).representation(using: .png, properties: [:])!
    try! data.write(to: URL(fileURLWithPath: "\(dir)/icon_\(name).png"))
}
