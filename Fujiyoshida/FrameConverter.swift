import CoreImage
import CoreVideo

final class FrameConverter {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var pool: CVPixelBufferPool?
    private let width = CGFloat(FujiyoshidaConfig.width)
    private let height = CGFloat(FujiyoshidaConfig.height)
    private let regionLock = NSLock()
    private var region = CGRect(x: 0, y: 0, width: 1, height: 1)
    private var size = CGSize.zero

    var visibleRegion: CGRect {
        regionLock.lock(); defer { regionLock.unlock() }
        return region
    }

    var sourceSize: CGSize {
        regionLock.lock(); defer { regionLock.unlock() }
        return size
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

    func pixelBuffer(fromJPEG data: Data, rotation: Int = 0) -> CVPixelBuffer? {
        guard let pool, let source = CIImage(data: data, options: [.applyOrientationProperty: true]) else { return nil }

        let framed: CIImage
        if rotation == 0 {
            framed = filled(source)
        } else {
            framed = rotated(source, by: rotation)
        }

        var buffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        context.render(framed, to: buffer)
        return buffer
    }

    private func filled(_ image: CIImage) -> CIImage {
        let scale = max(width / image.extent.width, height / image.extent.height)
        let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let visibleWidth = width / scaled.extent.width
        let visibleHeight = height / scaled.extent.height
        let pictureHeight = min(image.extent.width * 2 / 3 / image.extent.height, 1)
        regionLock.lock()
        region = CGRect(
            x: (1 - visibleWidth) / 2,
            y: (pictureHeight - visibleHeight) / 2 / pictureHeight,
            width: visibleWidth,
            height: visibleHeight / pictureHeight
        )
        size = image.extent.size
        regionLock.unlock()
        return centered(scaled)
    }

    private func rotated(_ source: CIImage, by rotation: Int) -> CIImage {
        let pictureHeight = min(source.extent.width * 2 / 3, source.extent.height)
        let picture = source.cropped(to: CGRect(
            x: source.extent.minX,
            y: source.extent.minY + (source.extent.height - pictureHeight) / 2,
            width: source.extent.width,
            height: pictureHeight
        ))
        let orientation: CGImagePropertyOrientation = rotation == 90 ? .right : rotation == 180 ? .down : .left
        let image = picture.oriented(orientation)
        let origin = image.extent.origin
        let turned = image.transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))

        regionLock.lock()
        size = source.extent.size
        regionLock.unlock()

        guard rotation != 180 else {
            let scale = max(width / turned.extent.width, height / turned.extent.height)
            return centered(turned.transformed(by: CGAffineTransform(scaleX: scale, y: scale)))
        }

        let fillScale = max(width / turned.extent.width, height / turned.extent.height)
        let background = centered(turned.transformed(by: CGAffineTransform(scaleX: fillScale, y: fillScale)))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: 40)
            .applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: -1.2])
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))

        let fitScale = min(width / turned.extent.width, height / turned.extent.height)
        let fitted = turned.transformed(by: CGAffineTransform(scaleX: fitScale, y: fitScale))
        let foreground = fitted.transformed(by: CGAffineTransform(
            translationX: (width - fitted.extent.width) / 2 - fitted.extent.minX,
            y: (height - fitted.extent.height) / 2 - fitted.extent.minY
        ))
        return foreground.composited(over: background)
    }

    private func centered(_ scaled: CIImage) -> CIImage {
        let offsetX = scaled.extent.minX + (scaled.extent.width - width) / 2
        let offsetY = scaled.extent.minY + (scaled.extent.height - height) / 2
        return scaled
            .transformed(by: CGAffineTransform(translationX: -offsetX, y: -offsetY))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
    }
}
