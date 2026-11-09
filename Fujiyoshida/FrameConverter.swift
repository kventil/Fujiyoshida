import CoreImage
import CoreVideo

final class FrameConverter {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var pool: CVPixelBufferPool?
    private let width = CGFloat(FujiyoshidaConfig.width)
    private let height = CGFloat(FujiyoshidaConfig.height)
    private let regionLock = NSLock()
    private var region = CGRect(x: 0, y: 0, width: 1, height: 1)

    var visibleRegion: CGRect {
        regionLock.lock(); defer { regionLock.unlock() }
        return region
    }

    init() {
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: FujiyoshidaConfig.pixelFormat,
            kCVPixelBufferWidthKey: Int(FujiyoshidaConfig.width),
            kCVPixelBufferHeightKey: Int(FujiyoshidaConfig.height),
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, attributes as CFDictionary, &pool)
    }

    func pixelBuffer(fromJPEG data: Data) -> CVPixelBuffer? {
        guard let pool, let image = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }

        let scale = max(width / image.extent.width, height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let visibleWidth = width / scaled.extent.width
        let visibleHeight = height / scaled.extent.height
        regionLock.lock()
        region = CGRect(x: (1 - visibleWidth) / 2, y: (1 - visibleHeight) / 2, width: visibleWidth, height: visibleHeight)
        regionLock.unlock()
        let offsetX = scaled.extent.minX + (scaled.extent.width - width) / 2
        let offsetY = scaled.extent.minY + (scaled.extent.height - height) / 2
        let framed = scaled
            .transformed(by: CGAffineTransform(translationX: -offsetX, y: -offsetY))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))

        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        context.render(framed, to: buffer)
        return buffer
    }
}
