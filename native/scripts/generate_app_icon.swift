#!/usr/bin/env swift
// Deterministic vector drawing for the app icon. No external image or package dependency.
import AppKit
import ImageIO
let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let folder = root.appendingPathComponent("App/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let sizes = [16, 32, 64, 128, 256, 512, 1024]
for size in sizes {
    let cg = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
        bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    let context = NSGraphicsContext(cgContext: cg, flipped: false)
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    NSColor(srgbRed: 0.075, green: 0.078, blue: 0.075, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: 1024, height: 1024)).fill()
    let font = NSFont.systemFont(ofSize: 690, weight: .semibold)
    let attributes: [NSAttributedString.Key: Any] = [.font: font,
        .foregroundColor: NSColor(srgbRed: 0.97, green: 0.965, blue: 0.95, alpha: 1)]
    let letter = "R" as NSString
    let bounds = letter.size(withAttributes: attributes)
    letter.draw(at: NSPoint(x: (1024 - bounds.width) / 2 - 12, y: (1024 - bounds.height) / 2 + 14), withAttributes: attributes)
    NSColor(srgbRed: 0.80, green: 0.28, blue: 0.19, alpha: 1).setFill()
    NSBezierPath(rect: NSRect(x: 326, y: 150, width: 160, height: 28)).fill()
    NSGraphicsContext.restoreGraphicsState()
    let url = folder.appendingPathComponent("Icon\(size).png")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, cg.makeImage()!, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("PNG write failed") }
}
print("Generated opaque RELAY icons at \(folder.path)")
