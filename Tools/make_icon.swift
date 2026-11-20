// Renders Resources/AppIcon.icns: a terracotta squircle with a recipe card and a frying pan.
// Usage: swift Tools/make_icon.swift <output-dir>
import AppKit

let out = CommandLine.arguments.dropFirst().first ?? "build"
let iconset = URL(fileURLWithPath: out).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.18, yRadius: s * 0.18)
    NSGradient(starting: NSColor(red: 0.90, green: 0.52, blue: 0.33, alpha: 1),
               ending: NSColor(red: 0.70, green: 0.30, blue: 0.18, alpha: 1))!.draw(in: bg, angle: -90)

    // Card
    let card = NSRect(x: s * 0.25, y: s * 0.22, width: s * 0.50, height: s * 0.58)
    NSGraphicsContext.current?.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowBlurRadius = s * 0.03; shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3); shadow.set()
    NSColor(red: 0.99, green: 0.97, blue: 0.92, alpha: 1).setFill()
    NSBezierPath(roundedRect: card, xRadius: s * 0.03, yRadius: s * 0.03).fill()
    NSGraphicsContext.current?.restoreGraphicsState()

    NSColor(red: 0.80, green: 0.40, blue: 0.24, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: card.minX + s * 0.05, y: card.maxY - s * 0.11, width: s * 0.28, height: s * 0.045),
                 xRadius: s * 0.02, yRadius: s * 0.02).fill()
    NSColor(white: 0.55, alpha: 1).setFill()
    for i in 0..<5 {
        let w = i % 2 == 0 ? s * 0.38 : s * 0.30
        NSBezierPath(roundedRect: NSRect(x: card.minX + s * 0.05, y: card.maxY - s * 0.19 - CGFloat(i) * s * 0.065,
                                         width: w, height: s * 0.022), xRadius: s * 0.01, yRadius: s * 0.01).fill()
    }
    // Version dots
    let dotColors: [NSColor] = [.systemGreen, .systemOrange, NSColor(red: 0.80, green: 0.40, blue: 0.24, alpha: 1)]
    for (i, c) in dotColors.enumerated() {
        c.setFill()
        NSBezierPath(ovalIn: NSRect(x: card.maxX - s * 0.14 + CGFloat(i) * s * 0.04 - s * 0.04, y: card.minY + s * 0.05,
                                    width: s * 0.03, height: s * 0.03)).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
print(iconset.path)
