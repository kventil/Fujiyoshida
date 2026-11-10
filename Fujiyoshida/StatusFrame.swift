import AppKit
import CoreVideo

struct StatusFrame: Hashable {
    let symbol: String
    let title: String
    let detail: String

    static let starting = StatusFrame(symbol: "camera", title: "Starting camera…", detail: "")
    static let noCamera = StatusFrame(
        symbol: "cable.connector",
        title: "No camera connected",
        detail: "Connect the X-T4 by USB, set it to USB Tether Shooting Auto and switch it on"
    )
    static let stuck = StatusFrame(
        symbol: "exclamationmark.triangle",
        title: "Camera isn't sending video",
        detail: "Set the STILL/MOVIE lever to STILL and close any open camera menus"
    )
    static let paused = StatusFrame(
        symbol: "pause.circle",
        title: "Camera paused",
        detail: "Resume it from the Fujiyoshida menu"
    )
}

final class StatusFrameRenderer {
    private var cache: [StatusFrame: CVPixelBuffer] = [:]

    func buffer(for frame: StatusFrame) -> CVPixelBuffer? {
        if let buffer = cache[frame] { return buffer }
        let buffer = render(frame)
        cache[frame] = buffer
        return buffer
    }

    private func render(_ frame: StatusFrame) -> CVPixelBuffer? {
        let width = Int(FujiyoshidaConfig.width)
        let height = Int(FujiyoshidaConfig.height)
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, FujiyoshidaConfig.pixelFormat, attributes as CFDictionary, &pixelBuffer)
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.restoreGraphicsState() }

        NSColor(calibratedRed: 0.07, green: 0.07, blue: 0.08, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let title = NSAttributedString(string: frame.title, attributes: [
            .font: NSFont.systemFont(ofSize: 46, weight: .semibold),
            .foregroundColor: NSColor(white: 0.93, alpha: 1),
            .paragraphStyle: paragraph,
        ])
        let detail = NSAttributedString(string: frame.detail, attributes: [
            .font: NSFont.systemFont(ofSize: 30, weight: .regular),
            .foregroundColor: NSColor(white: 0.6, alpha: 1),
            .paragraphStyle: paragraph,
        ])
        let symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 76, weight: .light)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(white: 0.55, alpha: 1)]))
        let symbol = NSImage(systemSymbolName: frame.symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(symbolConfiguration)

        let textWidth: CGFloat = 960
        let titleHeight = ceil(title.boundingRect(with: NSSize(width: textWidth, height: 400), options: .usesLineFragmentOrigin).height)
        let detailHeight = frame.detail.isEmpty ? 0 : ceil(detail.boundingRect(with: NSSize(width: textWidth, height: 400), options: .usesLineFragmentOrigin).height)
        let symbolSize = symbol?.size ?? .zero
        let total = symbolSize.height + 36 + titleHeight + (detailHeight > 0 ? 16 + detailHeight : 0)

        var top = (CGFloat(height) + total) / 2
        symbol?.draw(in: NSRect(x: (CGFloat(width) - symbolSize.width) / 2, y: top - symbolSize.height, width: symbolSize.width, height: symbolSize.height))
        top -= symbolSize.height + 36
        let textX = (CGFloat(width) - textWidth) / 2
        title.draw(with: NSRect(x: textX, y: top - titleHeight, width: textWidth, height: titleHeight), options: .usesLineFragmentOrigin)
        top -= titleHeight + 16
        if detailHeight > 0 {
            detail.draw(with: NSRect(x: textX, y: top - detailHeight, width: textWidth, height: detailHeight), options: .usesLineFragmentOrigin)
        }
        return pixelBuffer
    }
}
