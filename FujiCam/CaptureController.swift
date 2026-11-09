import Foundation

final class CaptureController: ObservableObject {
    @Published private(set) var status = "Idle"
    @Published private(set) var isRunning = false
    @Published private(set) var isStreaming = false
    @Published private(set) var info: CameraInfo?
    @Published private(set) var visibleRegion = CGRect(x: 0, y: 0, width: 1, height: 1)

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
        thread.name = "FujiCam capture"
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
            self.status = status
            self.isStreaming = streaming
        }
    }

    private func publishInfo(_ info: CameraInfo?, region: CGRect? = nil) {
        DispatchQueue.main.async {
            if self.info != info { self.info = info }
            if let region, self.visibleRegion != region { self.visibleRegion = region }
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
        let decodeQueue = DispatchQueue(label: "fujicam.decode", qos: .userInteractive)
        let decodeSlots = DispatchSemaphore(value: 2)
        var frameCount = 0
        var cameraTime: TimeInterval = 0
        var windowStart = Date()
        var lastInfoRead = Date.distantPast
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
                    publish("Connected to \(camera.modelName)", streaming: false)
                } catch {
                    publish("No camera found – USB connection mode must be “USB Tether Shooting”", streaming: false)
                    pause(2)
                    continue
                }
            }

            do {
                let requested = Date()
                let jpeg = try autoreleasepool { try camera.capturePreview() }
                cameraTime += Date().timeIntervalSince(requested)

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
                    publish("\(camera.modelName) · \(fps) fps · \(perFrame) ms/frame", streaming: true)
                    frameCount = 0
                    cameraTime = 0
                    windowStart = Date()
                }
            } catch {
                publish(error.localizedDescription, streaming: false)
                publishInfo(nil)
                camera.disconnect()
                pause(1)
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
            self.info = nil
            self.status = "Stopped"
        }
    }

}
