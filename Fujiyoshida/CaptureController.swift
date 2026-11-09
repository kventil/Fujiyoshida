import Foundation

final class LiveStats: ObservableObject {
    @Published fileprivate(set) var info: CameraInfo?
    @Published fileprivate(set) var visibleRegion = CGRect(x: 0, y: 0, width: 1, height: 1)
    @Published fileprivate(set) var rate = ""
    @Published fileprivate(set) var message: String?
}

final class CaptureController: ObservableObject {
    @Published private(set) var status = "Idle"
    @Published private(set) var isRunning = false
    @Published private(set) var isStreaming = false
    let live = LiveStats()
    @Published private(set) var isoChoices: [String] = []

    static var shutterForFrameRate: String { "1/\(Int(FujiyoshidaConfig.frameRate) * 2)" }

    private var pendingSettings: [(name: String, value: String)] = []

    func setShutterForFrameRate() {
        enqueueSetting("shutterspeed", value: Self.shutterForFrameRate)
    }

    func setISO(_ value: String) {
        enqueueSetting("iso", value: value)
    }

    private func enqueueSetting(_ name: String, value: String) {
        lock.lock(); pendingSettings.append((name, value)); lock.unlock()
    }

    private func takePendingSettings() -> [(name: String, value: String)] {
        lock.lock(); defer { lock.unlock() }
        let settings = pendingSettings
        pendingSettings.removeAll()
        return settings
    }

    private func applyPendingSettings(on camera: FujiCamera) {
        for setting in takePendingSettings() {
            let label = setting.name == "iso" ? "ISO \(Self.isoLabel(setting.value))" : "Shutter \(setting.value)"
            do {
                try camera.writeSetting(setting.name, value: setting.value)
                let actual = camera.readSettings([setting.name])[setting.name]
                if actual == setting.value {
                    showMessage("\(label) set")
                } else {
                    showMessage(Self.rejectionHint(for: setting.name, label: label))
                }
            } catch {
                showMessage(Self.rejectionHint(for: setting.name, label: label))
            }
        }
    }

    static func isoLabel(_ value: String) -> String {
        guard let number = Int(value) else { return value }
        return number < 0 ? "Auto" : value
    }

    private static func rejectionHint(for name: String, label: String) -> String {
        switch name {
        case "shutterspeed": return "Camera kept its shutter – turn the shutter dial to T to control it from Fujiyoshida"
        case "iso": return "Camera kept its ISO – set the ISO dial to its command position to control it from Fujiyoshida"
        default: return "Camera rejected \(label)"
        }
    }

    private func showMessage(_ text: String) {
        DispatchQueue.main.async {
            self.live.message = text
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if self.live.message == text { self.live.message = nil }
            }
        }
    }

    private static let noCameraStatus = "No camera – connect the X-T4 in USB Tether Shooting mode"
    private static let stuckCameraStatus = "Camera not sending live view – close camera menus or switch it off and on"

    let preview = PreviewSurface()

    private let lock = NSLock()
    private var stopRequested = false
    private var thread: Thread?
    private let finished = DispatchSemaphore(value: 0)

    func start() {
        guard thread == nil else { return }
        setStopRequested(false)
        isRunning = true
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "Fujiyoshida capture"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    func stop() {
        setStopRequested(true)
    }

    func stopAndWait(timeout: TimeInterval = 3) {
        guard thread != nil else { return }
        setStopRequested(true)
        _ = finished.wait(timeout: .now() + timeout)
    }

    private func setStopRequested(_ value: Bool) {
        lock.lock(); stopRequested = value; lock.unlock()
    }

    private var shouldStop: Bool {
        lock.lock(); defer { lock.unlock() }
        return stopRequested
    }

    private func publish(_ status: String, streaming: Bool) {
        DispatchQueue.main.async {
            if self.status != status { self.status = status }
            if self.isStreaming != streaming { self.isStreaming = streaming }
            if !streaming, !self.live.rate.isEmpty { self.live.rate = "" }
        }
    }

    private func publishRate(_ rate: String) {
        DispatchQueue.main.async {
            if self.live.rate != rate { self.live.rate = rate }
        }
    }

    private func publishInfo(_ info: CameraInfo?, region: CGRect? = nil) {
        DispatchQueue.main.async {
            if self.live.info != info { self.live.info = info }
            if let region, self.live.visibleRegion != region { self.live.visibleRegion = region }
        }
    }

    private func pause(_ seconds: TimeInterval) {
        let deadline = Date().addingTimeInterval(seconds)
        while !shouldStop, Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
    }

    private func run() {
        let camera = FujiCamera()
        let converter = FrameConverter()
        let sink = SinkFeeder()
        let decodeQueue = DispatchQueue(label: "fujiyoshida.decode", qos: .userInteractive)
        let decodeSlots = DispatchSemaphore(value: 2)
        var frameCount = 0
        var cameraTime: TimeInterval = 0
        var windowStart = Date()
        var lastInfoRead = Date.distantPast
        var failures = 0
        var streaming = false
        let preview = self.preview

        while !shouldStop {
            guard sink.connect() else {
                publish("Waiting for camera extension…", streaming: false)
                pause(1)
                continue
            }

            if !camera.isConnected {
                do {
                    try camera.connect()
                    if failures == 0 { publish("Connecting to \(camera.modelName)…", streaming: false) }
                    let isoChoices = camera.choices(for: "iso").filter { (Int($0) ?? 0) > 0 }
                    DispatchQueue.main.async { if self.isoChoices != isoChoices { self.isoChoices = isoChoices } }
                } catch {
                    publish(Self.noCameraStatus, streaming: false)
                    pause(2)
                    continue
                }
            }

            do {
                let requested = Date()
                let jpeg = try autoreleasepool { try camera.capturePreview() }
                cameraTime += Date().timeIntervalSince(requested)
                if !streaming {
                    streaming = true
                    failures = 0
                    publish("Streaming from \(camera.modelName)", streaming: true)
                }

                if decodeSlots.wait(timeout: .now()) == .success {
                    decodeQueue.async {
                        autoreleasepool {
                            if let buffer = converter.pixelBuffer(fromJPEG: jpeg) {
                                sink.send(buffer)
                                preview.show(buffer)
                            }
                        }
                        decodeSlots.signal()
                    }
                }

                applyPendingSettings(on: camera)

                if Date().timeIntervalSince(lastInfoRead) >= 0.25 {
                    lastInfoRead = Date()
                    var settings = camera.readSettings(CameraInfo.settingNames)
                    settings[CameraInfo.focusPointKey] = camera.readPropertyString(0xD347)
                    publishInfo(CameraInfo(settings: settings), region: converter.visibleRegion)
                }

                frameCount += 1
                let elapsed = Date().timeIntervalSince(windowStart)
                if elapsed >= 1 {
                    let fps = Int((Double(frameCount) / elapsed).rounded())
                    let perFrame = Int((cameraTime / Double(frameCount) * 1000).rounded())
                    publishRate("\(fps) fps · \(perFrame) ms/frame")
                    frameCount = 0
                    cameraTime = 0
                    windowStart = Date()
                }
            } catch {
                failures += 1
                streaming = false
                publish(Self.stuckCameraStatus, streaming: false)
                publishInfo(nil)
                camera.disconnect()
                pause(min(Double(failures), 5))
            }
        }

        decodeQueue.sync {}
        camera.disconnect()
        sink.disconnect()
        finished.signal()
        DispatchQueue.main.async {
            self.thread = nil
            self.isRunning = false
            self.isStreaming = false
            self.live.info = nil
            self.live.rate = ""
            self.status = "Stopped"
        }
    }

}
