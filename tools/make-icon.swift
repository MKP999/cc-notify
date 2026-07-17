// tools/make-icon.swift
// Draws a 1024px app icon: Anthropic-clay rounded square + white bell (SF Symbol).
// Usage: swift tools/make-icon.swift [output.png]
import AppKit

let size = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                 pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4,
                                 hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0) else {
    FileHandle.standardError.write("ERROR: failed to create bitmap rep\n".data(using: .utf8)!)
    exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let canvas = CGRect(x: 0, y: 0, width: size, height: size)

// 1) Clay rounded-square background (Anthropic #CC785C).
let bg = NSColor(srgbRed: 0xCC/255.0, green: 0x78/255.0, blue: 0x5C/255.0, alpha: 1)
let radius = CGFloat(size) * 0.2237
let bgPath = NSBezierPath(roundedRect: canvas, xRadius: radius, yRadius: radius)
bg.setFill()
bgPath.fill()

// 2) White bell (SF Symbol "bell.fill") tinted white, centered.
let symbolSize = CGFloat(size) * 0.58
let cfg = NSImage.SymbolConfiguration(pointSize: symbolSize, weight: .regular)
guard let baseBell = NSImage(systemSymbolName: "bell.fill", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) else {
    FileHandle.standardError.write("ERROR: failed to load SF Symbol\n".data(using: .utf8)!)
    exit(1)
}

// Tint: fill white, then mask with the bell glyph (destinationIn).
let tinted = NSImage(size: baseBell.size)
tinted.lockFocus()
let r = CGRect(origin: .zero, size: baseBell.size)
NSColor.white.setFill()
NSBezierPath(rect: r).fill()
baseBell.draw(in: r, from: r, operation: .destinationIn, fraction: 1.0)
tinted.unlockFocus()

// Draw centered, nudged down ~2% for optical centering.
let bw = baseBell.size.width, bh = baseBell.size.height
let drawRect = CGRect(x: (CGFloat(size) - bw) / 2,
                      y: (CGFloat(size) - bh) / 2 - CGFloat(size) * 0.02,
                      width: bw, height: bh)
tinted.draw(in: drawRect)

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:]) else {
    FileHandle.standardError.write("ERROR: failed to encode PNG\n".data(using: .utf8)!)
    exit(1)
}
do {
    try png.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath) (\(size)x\(size))")
} catch {
    FileHandle.standardError.write("ERROR: write failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
