import CoreMediaIO
import CoreText
import Foundation
import IOKit.audio
import os.log

private let log = Logger(subsystem: FujiyoshidaConfig.extensionBundleID, category: "extension")

final class ExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {
    private(set) var device: CMIOExtensionDevice!
    private var sourceStream: ExtensionSourceStream!
    private var sinkStream: ExtensionSinkStream!

    private let queue = DispatchQueue(label: "fujiyoshida.extension.timer", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var sourceActive = false
    private var sinkClient: CMIOExtensionClient?
    private var lastSinkFrameHostTime: UInt64 = 0
    private var placeholder: CMSampleBuffer?
    private let videoDescription: CMFormatDescription

    init(localizedName: String) {
        var description: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: FujiyoshidaConfig.pixelFormat,
            width: FujiyoshidaConfig.width,
            height: FujiyoshidaConfig.height,
            extensions: nil,
            formatDescriptionOut: &description
        )
        videoDescription = description!
        super.init()

        device = CMIOExtensionDevice(
            localizedName: localizedName,
            deviceID: UUID(uuidString: FujiyoshidaConfig.deviceUID)!,
            legacyDeviceID: FujiyoshidaConfig.deviceUID,
            source: self
        )

        let frameDuration = CMTime(value: 1, timescale: FujiyoshidaConfig.frameRate)
        let format = CMIOExtensionStreamFormat(
            formatDescription: videoDescription,
            maxFrameDuration: frameDuration,
            minFrameDuration: frameDuration,
            validFrameDurations: nil
        )

        sourceStream = ExtensionSourceStream(
            localizedName: "\(localizedName) Video",
            streamID: UUID(uuidString: FujiyoshidaConfig.sourceStreamUID)!,
            format: format,
            device: self
        )
        sinkStream = ExtensionSinkStream(
            localizedName: "\(localizedName) Sink",
            streamID: UUID(uuidString: FujiyoshidaConfig.sinkStreamUID)!,
            format: format,
            device: self
        )

        do {
            try device.addStream(sourceStream.stream)
            try device.addStream(sinkStream.stream)
        } catch {
            fatalError("Failed to add streams: \(error.localizedDescription)")
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let deviceProperties = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            deviceProperties.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            deviceProperties.model = "Fujiyoshida"
        }
        return deviceProperties
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    func startSourceStreaming() {
        queue.async { [self] in
            sourceActive = true
            startTimerIfNeeded()
        }
    }

    func stopSourceStreaming() {
        queue.async { [self] in
            sourceActive = false
            stopTimerIfIdle()
        }
    }

    func startSinkStreaming(client: CMIOExtensionClient) {
        queue.async { [self] in
            sinkClient = client
            startTimerIfNeeded()
        }
    }

    func stopSinkStreaming() {
        queue.async { [self] in
            sinkClient = nil
            stopTimerIfIdle()
        }
    }

    private func startTimerIfNeeded() {
        guard timer == nil else { return }
        let interval = 1.0 / Double(FujiyoshidaConfig.frameRate)
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: interval, leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in self?.tick() }
        timer.resume()
        self.timer = timer
    }

    private func stopTimerIfIdle() {
        guard !sourceActive, sinkClient == nil else { return }
        timer?.cancel()
        timer = nil
    }

    private func tick() {
        let now = CMClockGetTime(CMClockGetHostTimeClock())
        let nowNanos = UInt64(now.seconds * Double(NSEC_PER_SEC))

        if let client = sinkClient {
            sinkStream.stream.consumeSampleBuffer(from: client) { [weak self] buffer, sequence, _, _, _ in
                guard let self, let buffer else { return }
                self.queue.async {
                    self.lastSinkFrameHostTime = nowNanos
                    if self.sourceActive {
                        self.sourceStream.stream.send(buffer, discontinuity: [], hostTimeInNanoseconds: nowNanos)
                    }
                    let output = CMIOExtensionScheduledOutput(sequenceNumber: sequence, hostTimeInNanoseconds: nowNanos)
                    self.sinkStream.stream.notifyScheduledOutputChanged(output)
                }
            }
        }

        guard sourceActive else { return }
        let staleAfter: UInt64 = 1_000_000_000
        if nowNanos &- lastSinkFrameHostTime > staleAfter, let buffer = placeholderBuffer(at: now) {
            sourceStream.stream.send(buffer, discontinuity: [], hostTimeInNanoseconds: nowNanos)
        }
    }

    private func placeholderBuffer(at time: CMTime) -> CMSampleBuffer? {
        if placeholder == nil {
            placeholder = makePlaceholder()
        }
        guard let placeholder, let image = CMSampleBufferGetImageBuffer(placeholder) else { return nil }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: FujiyoshidaConfig.frameRate),
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        var output: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: image,
            formatDescription: videoDescription,
            sampleTiming: &timing,
            sampleBufferOut: &output
        )
        return output
    }

    private func makePlaceholder() -> CMSampleBuffer? {
        let attributes: [CFString: Any] = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(FujiyoshidaConfig.width),
            Int(FujiyoshidaConfig.height),
            FujiyoshidaConfig.pixelFormat,
            attributes as CFDictionary,
            &pixelBuffer
        )
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.setFillColor(CGColor(red: 0.08, green: 0.08, blue: 0.09, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        let font = CTFontCreateWithName("Helvetica Neue" as CFString, 40, nil)
        let text = NSAttributedString(string: "Waiting for Fujifilm camera…", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.75, alpha: 1),
        ])
        let line = CTLineCreateWithAttributedString(text)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.textPosition = CGPoint(
            x: (CGFloat(width) - bounds.width) / 2 - bounds.minX,
            y: (CGFloat(height) - bounds.height) / 2 - bounds.minY
        )
        CTLineDraw(line, context)

        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: FujiyoshidaConfig.frameRate),
            presentationTimeStamp: .zero,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: videoDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }
}

final class ExtensionSourceStream: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private unowned let device: ExtensionDeviceSource
    private let format: CMIOExtensionStreamFormat

    init(localizedName: String, streamID: UUID, format: CMIOExtensionStreamFormat, device: ExtensionDeviceSource) {
        self.device = device
        self.format = format
        super.init()
        stream = CMIOExtensionStream(
            localizedName: localizedName,
            streamID: streamID,
            direction: .source,
            clockType: .hostTime,
            source: self
        )
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = CMTime(value: 1, timescale: FujiyoshidaConfig.frameRate)
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }

    func startStream() throws { device.startSourceStreaming() }

    func stopStream() throws { device.stopSourceStreaming() }
}

final class ExtensionSinkStream: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private unowned let device: ExtensionDeviceSource
    private let format: CMIOExtensionStreamFormat
    private var client: CMIOExtensionClient?

    init(localizedName: String, streamID: UUID, format: CMIOExtensionStreamFormat, device: ExtensionDeviceSource) {
        self.device = device
        self.format = format
        super.init()
        stream = CMIOExtensionStream(
            localizedName: localizedName,
            streamID: streamID,
            direction: .sink,
            clockType: .hostTime,
            source: self
        )
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }

    var availableProperties: Set<CMIOExtensionProperty> {
        [
            .streamActiveFormatIndex,
            .streamFrameDuration,
            .streamSinkBufferQueueSize,
            .streamSinkBuffersRequiredForStartup,
            .streamSinkBufferUnderrunCount,
            .streamSinkEndOfData,
        ]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            streamProperties.frameDuration = CMTime(value: 1, timescale: FujiyoshidaConfig.frameRate)
        }
        if properties.contains(.streamSinkBufferQueueSize) {
            streamProperties.sinkBufferQueueSize = 1
        }
        if properties.contains(.streamSinkBuffersRequiredForStartup) {
            streamProperties.sinkBuffersRequiredForStartup = 1
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        self.client = client
        return true
    }

    func startStream() throws {
        guard let client else { throw NSError(domain: "Fujiyoshida", code: 1) }
        log.info("Sink stream started")
        device.startSinkStreaming(client: client)
    }

    func stopStream() throws {
        log.info("Sink stream stopped")
        device.stopSinkStreaming()
    }
}

final class ExtensionProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private var deviceSource: ExtensionDeviceSource!

    init(clientQueue: DispatchQueue?) {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: clientQueue)
        deviceSource = ExtensionDeviceSource(localizedName: FujiyoshidaConfig.deviceName)
        do {
            try provider.addDevice(deviceSource.device)
        } catch {
            fatalError("Failed to add device: \(error.localizedDescription)")
        }
    }

    func connect(to client: CMIOExtensionClient) throws {}

    func disconnect(from client: CMIOExtensionClient) {}

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerManufacturer]
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let providerProperties = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerManufacturer) {
            providerProperties.manufacturer = "Fujiyoshida"
        }
        return providerProperties
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {}
}
