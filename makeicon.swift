// swift makeicon.swift <out.icns> -- draws the Fold app icon.
import AppKit

func draw(_ s: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let body = NSBezierPath(roundedRect: rect, xRadius: s * 0.2237, yRadius: s * 0.2237)
    ctx.saveGState()
    body.addClip()
    let bg = NSGradient(colors: [NSColor(srgbRed: 0.16, green: 0.18, blue: 0.23, alpha: 1),
                                NSColor(srgbRed: 0.05, green: 0.05, blue: 0.07, alpha: 1)])!
    bg.draw(in: rect, angle: -90)

    // The fold: a pane hinged along its lower edge, tipping away from the viewer.
    let w = rect.width, h = rect.height, x0 = rect.minX, y0 = rect.minY
    let hingeY = y0 + h * 0.30
    let topY = y0 + h * 0.78
    let lower = NSBezierPath()
    lower.move(to: CGPoint(x: x0 + w * 0.16, y: y0 + h * 0.14))
    lower.line(to: CGPoint(x: x0 + w * 0.84, y: y0 + h * 0.14))
    lower.line(to: CGPoint(x: x0 + w * 0.78, y: hingeY))
    lower.line(to: CGPoint(x: x0 + w * 0.22, y: hingeY))
    lower.close()
    NSColor(srgbRed: 0.55, green: 0.62, blue: 0.78, alpha: 0.35).setFill()
    lower.fill()

    let upper = NSBezierPath()
    upper.move(to: CGPoint(x: x0 + w * 0.22, y: hingeY))
    upper.line(to: CGPoint(x: x0 + w * 0.78, y: hingeY))
    upper.line(to: CGPoint(x: x0 + w * 0.66, y: topY))
    upper.line(to: CGPoint(x: x0 + w * 0.34, y: topY))
    upper.close()
    ctx.saveGState()
    upper.addClip()
    NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.99, blue: 1.0, alpha: 0.95),
                        NSColor(srgbRed: 0.58, green: 0.72, blue: 0.98, alpha: 0.55)])!
        .draw(in: CGRect(x: x0, y: hingeY, width: w, height: topY - hingeY), angle: 90)
    ctx.restoreGState()

    // Crease highlight.
    let crease = NSBezierPath()
    crease.move(to: CGPoint(x: x0 + w * 0.22, y: hingeY))
    crease.line(to: CGPoint(x: x0 + w * 0.78, y: hingeY))
    crease.lineWidth = max(1, s * 0.012)
    NSColor(white: 1, alpha: 0.9).setStroke()
    crease.stroke()

    ctx.restoreGState()
    img.unlockFocus()
    return img
}

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.icns"
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Fold.iconset")
try? FileManager.default.removeItem(at: set)
try! FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)

for (px, name) in [(16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"),
                   (128, "128x128"), (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"),
                   (512, "512x512"), (1024, "512x512@2x")] {
    let img = draw(CGFloat(px))
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    img.draw(in: CGRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!
        .write(to: set.appendingPathComponent("icon_\(name).png"))
}

let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", set.path, "-o", out]
try! p.run(); p.waitUntilExit()
print(p.terminationStatus == 0 ? "wrote \(out)" : "iconutil failed")
