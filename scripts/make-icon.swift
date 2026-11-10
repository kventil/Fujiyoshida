import AppKit
import CoreGraphics

let outputDirectory = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Fujiyoshida/Assets.xcassets/AppIcon.appiconset"
let canvas: CGFloat = 1024

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func linearGradient(_ context: CGContext, _ colors: [CGColor], from start: CGPoint, to end: CGPoint, locations: [CGFloat]? = nil) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    context.drawLinearGradient(gradient, start: start, end: end, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radialGradient(_ context: CGContext, _ colors: [CGColor], center: CGPoint, radius: CGFloat, locations: [CGFloat]? = nil) {
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: locations)!
    context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [.drawsAfterEndLocation])
}

func drawIcon(in context: CGContext) {
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 186, cornerHeight: 186, transform: nil)

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: color(0x000000, 0.35))
    context.addPath(bodyPath)
    context.setFillColor(color(0xD9D9DE))
    context.fillPath()
    context.restoreGState()

    context.saveGState()
    context.addPath(bodyPath)
    context.clip()
    linearGradient(context, [color(0xF7F7F9), color(0xD2D3D9), color(0xB9BAC2)], from: CGPoint(x: 0, y: body.maxY), to: CGPoint(x: 0, y: body.minY), locations: [0, 0.55, 1])
    let band = CGRect(x: body.minX, y: body.minY, width: body.width, height: 250)
    context.setFillColor(color(0x232428))
    context.fill(band)
    for row in stride(from: band.minY + 10, to: band.maxY, by: 16) {
        for column in stride(from: band.minX + (Int(row) % 32 == 0 ? 8 : 0), to: band.maxX, by: 16) {
            context.setFillColor(color(0x2E2F34))
            context.fillEllipse(in: CGRect(x: column, y: row, width: 7, height: 7))
        }
    }
    context.restoreGState()

    let center = CGPoint(x: 512, y: 512)
    let barrel: CGFloat = 330
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(0x000000, 0.45))
    context.setFillColor(color(0x16171A))
    context.fillEllipse(in: CGRect(x: center.x - barrel, y: center.y - barrel, width: barrel * 2, height: barrel * 2))
    context.restoreGState()

    context.saveGState()
    context.addEllipse(in: CGRect(x: center.x - barrel, y: center.y - barrel, width: barrel * 2, height: barrel * 2))
    context.clip()
    linearGradient(context, [color(0x3A3B41), color(0x0E0F11)], from: CGPoint(x: 0, y: center.y + barrel), to: CGPoint(x: 0, y: center.y - barrel))
    context.restoreGState()

    for index in 0..<60 {
        let angle = CGFloat(index) / 60 * .pi * 2
        let inner = barrel - 34, outer = barrel - 8
        context.move(to: CGPoint(x: center.x + cos(angle) * inner, y: center.y + sin(angle) * inner))
        context.addLine(to: CGPoint(x: center.x + cos(angle) * outer, y: center.y + sin(angle) * outer))
    }
    context.setStrokeColor(color(0x55565C))
    context.setLineWidth(5)
    context.strokePath()

    let ring: CGFloat = 268
    context.setStrokeColor(color(0x8A8B92))
    context.setLineWidth(4)
    context.strokeEllipse(in: CGRect(x: center.x - ring, y: center.y - ring, width: ring * 2, height: ring * 2))

    let glass: CGFloat = 238
    let glassRect = CGRect(x: center.x - glass, y: center.y - glass, width: glass * 2, height: glass * 2)
    context.saveGState()
    context.addEllipse(in: glassRect)
    context.clip()

    linearGradient(context, [color(0x1C2350), color(0x5A4A8C), color(0xE58C6C), color(0xF6C48A)], from: CGPoint(x: 0, y: glassRect.maxY), to: CGPoint(x: 0, y: center.y - 70), locations: [0, 0.45, 0.82, 1])

    context.setFillColor(color(0xE8453C))
    context.fillEllipse(in: CGRect(x: center.x + 70, y: center.y + 50, width: 92, height: 92))

    let base = center.y - 120
    let mountain = CGMutablePath()
    mountain.move(to: CGPoint(x: glassRect.minX - 20, y: base - 40))
    mountain.addCurve(to: CGPoint(x: center.x - 70, y: center.y + 70), control1: CGPoint(x: center.x - 200, y: base + 20), control2: CGPoint(x: center.x - 120, y: center.y + 20))
    mountain.addLine(to: CGPoint(x: center.x + 60, y: center.y + 70))
    mountain.addCurve(to: CGPoint(x: glassRect.maxX + 20, y: base - 40), control1: CGPoint(x: center.x + 110, y: center.y + 20), control2: CGPoint(x: center.x + 200, y: base + 20))
    mountain.addLine(to: CGPoint(x: glassRect.maxX + 20, y: glassRect.minY - 20))
    mountain.addLine(to: CGPoint(x: glassRect.minX - 20, y: glassRect.minY - 20))
    mountain.closeSubpath()
    context.addPath(mountain)
    context.saveGState()
    context.clip()
    linearGradient(context, [color(0x3B4677), color(0x1A1F3C)], from: CGPoint(x: 0, y: center.y + 70), to: CGPoint(x: 0, y: glassRect.minY))
    context.restoreGState()

    let snow = CGMutablePath()
    snow.move(to: CGPoint(x: center.x - 70, y: center.y + 70))
    snow.addLine(to: CGPoint(x: center.x + 60, y: center.y + 70))
    snow.addCurve(to: CGPoint(x: center.x + 118, y: center.y - 2), control1: CGPoint(x: center.x + 86, y: center.y + 40), control2: CGPoint(x: center.x + 104, y: center.y + 16))
    snow.addLine(to: CGPoint(x: center.x + 80, y: center.y + 14))
    snow.addLine(to: CGPoint(x: center.x + 48, y: center.y - 14))
    snow.addLine(to: CGPoint(x: center.x + 14, y: center.y + 16))
    snow.addLine(to: CGPoint(x: center.x - 22, y: center.y - 12))
    snow.addLine(to: CGPoint(x: center.x - 58, y: center.y + 16))
    snow.addLine(to: CGPoint(x: center.x - 126, y: center.y - 2))
    snow.addCurve(to: CGPoint(x: center.x - 70, y: center.y + 70), control1: CGPoint(x: center.x - 108, y: center.y + 18), control2: CGPoint(x: center.x - 90, y: center.y + 40))
    snow.closeSubpath()
    context.addPath(snow)
    context.setFillColor(color(0xF4F6FB))
    context.fillPath()

    linearGradient(context, [color(0x0B0F24, 0), color(0x0B0F24, 0.55)], from: CGPoint(x: 0, y: center.y - 60), to: CGPoint(x: 0, y: glassRect.minY))

    radialGradient(context, [color(0xFFFFFF, 0.0), color(0x000000, 0.45)], center: center, radius: glass, locations: [0.62, 1])

    let highlight = CGMutablePath()
    highlight.addArc(center: center, radius: glass - 26, startAngle: .pi * 0.58, endAngle: .pi * 0.92, clockwise: false)
    context.addPath(highlight)
    context.setStrokeColor(color(0xFFFFFF, 0.55))
    context.setLineWidth(14)
    context.setLineCap(.round)
    context.strokePath()
    context.setFillColor(color(0xFFFFFF, 0.35))
    context.fillEllipse(in: CGRect(x: center.x + 120, y: center.y - 150, width: 34, height: 34))
    context.restoreGState()

    context.setStrokeColor(color(0x000000, 0.6))
    context.setLineWidth(6)
    context.strokeEllipse(in: glassRect)
}

func render(size: Int) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    let graphics = NSGraphicsContext(bitmapImageRep: rep)!
    let context = graphics.cgContext
    context.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    context.interpolationQuality = .high
    drawIcon(in: context)
    graphics.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

let entries: [(points: Int, scale: Int)] = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
var images: [[String: String]] = []
for entry in entries {
    let pixels = entry.points * entry.scale
    let name = "icon_\(entry.points)x\(entry.points)\(entry.scale == 2 ? "@2x" : "").png"
    try render(size: pixels).write(to: URL(fileURLWithPath: outputDirectory).appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(entry.points)x\(entry.points)", "scale": "\(entry.scale)x", "filename": name])
}
let contents: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let json = try JSONSerialization.data(withJSONObject: contents, options: [.prettyPrinted, .sortedKeys])
try json.write(to: URL(fileURLWithPath: outputDirectory).appendingPathComponent("Contents.json"))
let catalog = URL(fileURLWithPath: outputDirectory).deletingLastPathComponent().appendingPathComponent("Contents.json")
try #"{"info":{"author":"xcode","version":1}}"#.data(using: .utf8)!.write(to: catalog)
