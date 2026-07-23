#!/usr/bin/env swift

import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
    fputs("Usage: generate-app-icon.swift <output.iconset>\n", stderr)
    exit(64)
}

let outputDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

func scaled(_ value: CGFloat, for size: CGFloat) -> CGFloat {
    value * size / 1024
}

for variant in variants {
    let size = CGFloat(variant.pixels)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: variant.pixels,
        pixelsHigh: variant.pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }

    bitmap.size = NSSize(width: size, height: size)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

    NSColor.clear.setFill()
    NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

    let outer = NSBezierPath(
        roundedRect: NSRect(x: 0, y: 0, width: size, height: size),
        xRadius: scaled(224, for: size),
        yRadius: scaled(224, for: size)
    )
    NSColor(red: 13 / 255, green: 10 / 255, blue: 10 / 255, alpha: 1).setFill()
    outer.fill()

    let inset = scaled(104, for: size)
    let paper = NSBezierPath(
        roundedRect: NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2),
        xRadius: scaled(144, for: size),
        yRadius: scaled(144, for: size)
    )
    NSColor.white.setFill()
    paper.fill()

    func rule(from start: NSPoint, to end: NSPoint, width: CGFloat, color: NSColor) {
        let path = NSBezierPath()
        path.move(to: start)
        path.line(to: end)
        path.lineWidth = width
        color.setStroke()
        path.stroke()
    }

    rule(
        from: NSPoint(x: inset, y: scaled(324, for: size)),
        to: NSPoint(x: size - inset, y: scaled(324, for: size)),
        width: max(1, scaled(12, for: size)),
        color: NSColor(white: 224 / 255, alpha: 1)
    )
    rule(
        from: NSPoint(x: inset, y: scaled(700, for: size)),
        to: NSPoint(x: size - inset, y: scaled(700, for: size)),
        width: max(1, scaled(12, for: size)),
        color: NSColor(white: 224 / 255, alpha: 1)
    )
    rule(
        from: NSPoint(x: scaled(324, for: size), y: inset),
        to: NSPoint(x: scaled(324, for: size), y: size - inset),
        width: max(1, scaled(8, for: size)),
        color: NSColor(white: 237 / 255, alpha: 1)
    )
    rule(
        from: NSPoint(x: scaled(700, for: size), y: inset),
        to: NSPoint(x: scaled(700, for: size), y: size - inset),
        width: max(1, scaled(8, for: size)),
        color: NSColor(white: 237 / 255, alpha: 1)
    )

    let font = NSFont(name: "Times New Roman Bold", size: scaled(380, for: size))
        ?? NSFont.systemFont(ofSize: scaled(380, for: size), weight: .bold)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(red: 13 / 255, green: 10 / 255, blue: 10 / 255, alpha: 1),
        .paragraphStyle: paragraph,
    ]
    ("99" as NSString).draw(
        in: NSRect(x: 0, y: scaled(286, for: size), width: size, height: scaled(440, for: size)),
        withAttributes: attributes
    )

    let seal = NSRect(
        x: scaled(744, for: size),
        y: scaled(160, for: size),
        width: scaled(120, for: size),
        height: scaled(120, for: size)
    )
    NSColor(red: 194 / 255, green: 58 / 255, blue: 46 / 255, alpha: 1).setFill()
    NSBezierPath(rect: seal).fill()
    rule(
        from: NSPoint(x: scaled(768, for: size), y: scaled(220, for: size)),
        to: NSPoint(x: scaled(840, for: size), y: scaled(220, for: size)),
        width: max(1, scaled(16, for: size)),
        color: .white
    )
    rule(
        from: NSPoint(x: scaled(804, for: size), y: scaled(184, for: size)),
        to: NSPoint(x: scaled(804, for: size), y: scaled(256, for: size)),
        width: max(1, scaled(16, for: size)),
        color: .white
    )

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: outputDirectory.appendingPathComponent(variant.name), options: .atomic)
}
