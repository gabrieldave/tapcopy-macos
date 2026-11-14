import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Builds a clean, emoji-free AppIcon.iconset: dark aluminum squircle with a
// minimal light capsule (the "copy pill") in the center.

let arguments = CommandLine.arguments
let outputPath = arguments.count > 1 ? arguments[1] : "./AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

struct IconEntry {
    let name: String
    let pixels: Int
}

let entries: [IconEntry] = [
    IconEntry(name: "icon_16x16.png", pixels: 16),
    IconEntry(name: "icon_16x16@2x.png", pixels: 32),
    IconEntry(name: "icon_32x32.png", pixels: 32),
    IconEntry(name: "icon_32x32@2x.png", pixels: 64),
    IconEntry(name: "icon_128x128.png", pixels: 128),
    IconEntry(name: "icon_128x128@2x.png", pixels: 256),
    IconEntry(name: "icon_256x256.png", pixels: 256),
    IconEntry(name: "icon_256x256@2x.png", pixels: 512),
    IconEntry(name: "icon_512x512.png", pixels: 512),
    IconEntry(name: "icon_512x512@2x.png", pixels: 1024)
]

func color(_ hex: UInt32, alpha: CGFloat = 1.0) -> CGColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return CGColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

func render(pixels: Int) -> CGImage? {
    let size = CGFloat(pixels)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: pixels,
        height: pixels,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    // Squircle body (#111318 aluminium).
    let inset = size * 0.045
    let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
    let radius = body.width * 0.2237
    let bodyPath = CGPath(roundedRect: body, cornerWidth: radius, cornerHeight: radius, transform: nil)

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()

    let gradient = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0x1A1C21), color(0x0D0E11)] as CFArray,
        locations: [0.0, 1.0]
    )
    if let gradient {
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: 0, y: size),
            end: CGPoint(x: 0, y: 0),
            options: []
        )
    }

    // Soft top sheen.
    let sheen = CGGradient(
        colorsSpace: colorSpace,
        colors: [color(0xFFFFFF, alpha: 0.07), color(0xFFFFFF, alpha: 0.0)] as CFArray,
        locations: [0.0, 1.0]
    )
    if let sheen {
        context.drawLinearGradient(
            sheen,
            start: CGPoint(x: size * 0.5, y: size),
            end: CGPoint(x: size * 0.5, y: size * 0.55),
            options: []
        )
    }
    context.restoreGState()

    // Hairline edge.
    context.addPath(bodyPath)
    context.setStrokeColor(color(0xFFFFFF, alpha: 0.12))
    context.setLineWidth(max(1.0, size * 0.006))
    context.strokePath()

    // Capsule pill.
    let pillWidth = body.width * 0.60
    let pillHeight = body.height * 0.245
    let pillRect = CGRect(
        x: (size - pillWidth) / 2.0,
        y: (size - pillHeight) / 2.0,
        width: pillWidth,
        height: pillHeight
    )
    let pillPath = CGPath(
        roundedRect: pillRect,
        cornerWidth: pillHeight / 2.0,
        cornerHeight: pillHeight / 2.0,
        transform: nil
    )
    context.addPath(pillPath)
    context.setFillColor(color(0xF4F4F5))
    context.fillPath()

    // Minimal document glyph inside the pill (two overlapping sheets).
    let glyphWidth = pillHeight * 0.52
    let glyphHeight = pillHeight * 0.62
    let lineWidth = max(1.0, size * 0.011)
    let backRect = CGRect(
        x: pillRect.midX - glyphWidth * 0.78,
        y: pillRect.midY - glyphHeight * 0.35,
        width: glyphWidth,
        height: glyphHeight
    )
    let frontRect = CGRect(
        x: pillRect.midX - glyphWidth * 0.30,
        y: pillRect.midY - glyphHeight * 0.62,
        width: glyphWidth,
        height: glyphHeight
    )
    let glyphRadius = glyphWidth * 0.22

    context.setStrokeColor(color(0x1E1F22))
    context.setLineWidth(lineWidth)
    context.setLineJoin(.round)

    // Clear the back sheet behind the front one.
    context.setFillColor(color(0xF4F4F5))
    context.fill(frontRect.insetBy(dx: -lineWidth, dy: -lineWidth))

    context.addPath(CGPath(roundedRect: backRect, cornerWidth: glyphRadius, cornerHeight: glyphRadius, transform: nil))
    context.strokePath()
    context.addPath(CGPath(roundedRect: frontRect, cornerWidth: glyphRadius, cornerHeight: glyphRadius, transform: nil))
    context.strokePath()

    return context.makeImage()
}

func write(_ image: CGImage, to url: URL) {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
    ) else {
        FileHandle.standardError.write("No se pudo crear \(url.path)\n".data(using: .utf8)!)
        return
    }
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

var renderedCount = 0
for entry in entries {
    let url = outputURL.appendingPathComponent(entry.name)
    guard let image = render(pixels: entry.pixels) else {
        FileHandle.standardError.write("Fallo al renderizar \(entry.name)\n".data(using: .utf8)!)
        exit(1)
    }
    write(image, to: url)
    renderedCount += 1
}

print("Iconos generados: \(renderedCount) en \(outputPath)")
