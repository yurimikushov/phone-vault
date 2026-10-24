import AppKit

func renderIcon(size: CGFloat) -> NSImage {
    let img = NSImage(size: NSSize(width: size, height: size))
    img.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        img.unlockFocus()
        return img
    }

    let rect = CGRect(x: 0, y: 0, width: size, height: size)

    // Rounded rectangle background (macOS squircle approx: cornerRadius = 0.224 * size)
    let cornerRadius = size * 0.224
    let path = CGPath(roundedRect: rect.insetBy(dx: size * 0.04, dy: size * 0.04),
                      cornerWidth: cornerRadius,
                      cornerHeight: cornerRadius,
                      transform: nil)
    ctx.addPath(path)
    ctx.clip()

    // Background gradient: Dark slate blue to deep indigo
    let colors = [
        CGColor(red: 0.10, green: 0.15, blue: 0.32, alpha: 1.0),
        CGColor(red: 0.04, green: 0.06, blue: 0.16, alpha: 1.0)
    ] as CFArray
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    if let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: size * 0.5, y: size * 0.96),
                               end: CGPoint(x: size * 0.5, y: size * 0.04),
                               options: [])
    }

    // Inner subtle glow border
    ctx.addPath(path)
    ctx.setStrokeColor(CGColor(red: 0.3, green: 0.5, blue: 0.9, alpha: 0.35))
    ctx.setLineWidth(size * 0.015)
    ctx.strokePath()

    // Draw iPhone silhouette
    let phoneWidth = size * 0.42
    let phoneHeight = size * 0.68
    let phoneX = (size - phoneWidth) / 2
    let phoneY = (size - phoneHeight) / 2
    let phoneRect = CGRect(x: phoneX, y: phoneY, width: phoneWidth, height: phoneHeight)
    let phoneCorner = size * 0.075

    // Phone shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -size * 0.02),
                  blur: size * 0.05,
                  color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.6))

    let phonePath = CGPath(roundedRect: phoneRect,
                           cornerWidth: phoneCorner,
                           cornerHeight: phoneCorner,
                           transform: nil)
    ctx.addPath(phonePath)
    ctx.setFillColor(CGColor(red: 0.15, green: 0.22, blue: 0.42, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Phone outer border
    ctx.addPath(phonePath)
    ctx.setStrokeColor(CGColor(red: 0.38, green: 0.55, blue: 0.88, alpha: 0.8))
    ctx.setLineWidth(size * 0.015)
    ctx.strokePath()

    // Screen area
    let screenInsetX = phoneWidth * 0.07
    let screenInsetY = phoneHeight * 0.09
    let screenRect = phoneRect.insetBy(dx: screenInsetX, dy: screenInsetY)
    let screenPath = CGPath(roundedRect: screenRect,
                            cornerWidth: phoneCorner * 0.7,
                            cornerHeight: phoneCorner * 0.7,
                            transform: nil)
    ctx.addPath(screenPath)
    ctx.setFillColor(CGColor(red: 0.06, green: 0.09, blue: 0.20, alpha: 1.0))
    ctx.fillPath()

    // Vault Lock / Shield Symbol inside screen
    let centerX = size * 0.5
    let centerY = size * 0.5

    // Vault outer dial circle
    let dialRadius = size * 0.13
    let dialRect = CGRect(x: centerX - dialRadius, y: centerY - dialRadius, width: dialRadius * 2, height: dialRadius * 2)
    ctx.addEllipse(in: dialRect)
    ctx.setStrokeColor(CGColor(red: 0.25, green: 0.72, blue: 0.95, alpha: 0.9))
    ctx.setLineWidth(size * 0.02)
    ctx.strokePath()

    // Inner dial circle
    let innerRadius = size * 0.065
    let innerRect = CGRect(x: centerX - innerRadius, y: centerY - innerRadius, width: innerRadius * 2, height: innerRadius * 2)
    ctx.addEllipse(in: innerRect)
    ctx.setFillColor(CGColor(red: 0.25, green: 0.72, blue: 0.95, alpha: 1.0))
    ctx.fillPath()

    // Keyhole / notch
    let notchWidth = size * 0.022
    let notchHeight = size * 0.065
    let notchRect = CGRect(x: centerX - notchWidth / 2, y: centerY - notchHeight * 0.9, width: notchWidth, height: notchHeight)
    ctx.addRect(notchRect)
    ctx.setFillColor(CGColor(red: 0.06, green: 0.09, blue: 0.20, alpha: 1.0))
    ctx.fillPath()

    // Dial spokes
    for i in 0..<8 {
        let angle = Double(i) * (.pi / 4.0)
        let r1 = dialRadius * 0.75
        let r2 = dialRadius * 0.98
        let p1 = CGPoint(x: centerX + CGFloat(cos(angle)) * r1, y: centerY + CGFloat(sin(angle)) * r1)
        let p2 = CGPoint(x: centerX + CGFloat(cos(angle)) * r2, y: centerY + CGFloat(sin(angle)) * r2)
        ctx.move(to: p1)
        ctx.addLine(to: p2)
        ctx.setStrokeColor(CGColor(red: 0.25, green: 0.72, blue: 0.95, alpha: 0.7))
        ctx.setLineWidth(size * 0.015)
        ctx.strokePath()
    }

    img.unlockFocus()
    return img
}

func savePNG(image: NSImage, at url: URL, pixelSize: Int) throws {
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "IconError", code: 1)
    }

    rep.size = NSSize(width: pixelSize, height: pixelSize)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy,
               fraction: 1.0)
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = rep.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "IconError", code: 2)
    }
    try pngData.write(to: url)
}

func generateIconset(at destinationDir: URL) throws {
    let fm = FileManager.default
    try fm.createDirectory(at: destinationDir, withIntermediateDirectories: true)

    let sizes: [(name: String, px: Int)] = [
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

    let masterImage = renderIcon(size: 1024)
    for entry in sizes {
        let dest = destinationDir.appendingPathComponent(entry.name)
        try savePNG(image: masterImage, at: dest, pixelSize: entry.px)
    }
}

func compileIconset(iconsetDir: URL, to outputIcns: URL) throws {
    let parentDir = outputIcns.deletingLastPathComponent()
    if !parentDir.path.isEmpty {
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetDir.path, "-o", outputIcns.path]

    let errorPipe = Pipe()
    process.standardError = errorPipe

    try process.run()
    process.waitUntilExit()

    if process.terminationStatus != 0 {
        let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let errMsg = String(data: errData, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: "IconUtilError", code: Int(process.terminationStatus),
                      userInfo: [NSLocalizedDescriptionKey: errMsg])
    }
}

let fm = FileManager.default

let defaultOutputPath: String
if fm.fileExists(atPath: "resources") {
    defaultOutputPath = "resources/AppIcon.icns"
} else {
    defaultOutputPath = "AppIcon.icns"
}

let targetArg = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : defaultOutputPath
let targetURL = URL(fileURLWithPath: targetArg)

if targetURL.pathExtension == "iconset" {
    try generateIconset(at: targetURL)
    print("Generated iconset at \(targetURL.path)")
} else {
    // Generate into a temporary .iconset, then compile to .icns with iconutil
    let tempIconset = fm.temporaryDirectory.appendingPathComponent("AppIcon-\(UUID().uuidString).iconset")
    try generateIconset(at: tempIconset)
    defer {
        try? fm.removeItem(at: tempIconset)
    }

    try compileIconset(iconsetDir: tempIconset, to: targetURL)
    print("Generated AppIcon at \(targetURL.path)")
}
