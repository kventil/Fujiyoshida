import Foundation

final class LiveStats: ObservableObject {
    @Published fileprivate(set) var info: CameraInfo?
    @Published fileprivate(set) var visibleRegion = CGRect(x: 0, y: 0, width: 1, height: 1)
    @Published fileprivate(set) var rate = ""
    @Published fileprivate(set) var message: String?
}

final class CaptureController: ObservableObject {
    enum State {
        case paused, waitingForExtension, standby, noCamera, connecting, streaming, stuck
    }

    private enum Command {
        case apply([CameraSetting])
        case focusArea(String)
        case focusNow
    }

    @Published private(set) var status = "Starting…"
    @Published private(set) var state = State.standby
    @Published private(set) var isPaused = false
    @Published private(set) var batteryLevel: Int?
    @Published private(set) var rotation = UserDefaults.standard.integer(forKey: "rotation")
    var isBatteryLow: Bool { (batteryLevel ?? 100) < CameraInfo.lowBatteryLevel }
    @Published private(set) var overrides = CameraSettingsStore.loadOverrides()
    @Published private(set) var choices = CameraSettingsStore.loadChoices()
    var isStreaming: Bool { state == .streaming }

    let live = LiveStats()
    let preview = PreviewSurface()

    private static let focusAreaProperty: UInt16 = 0xD395
    private static let currentFocusProperty: UInt16 = 0xD347
    private static let batteryStateProperty: UInt16 = 0xD36A

    private let lock = NSLock()
    private var stopRequested = false
    private var pausedFlag = false
    private var rotationFlag = UserDefaults.standard.integer(forKey: "rotation")
    private var commands: [Command] = []
    private var targetOverrides: [CameraSetting: String] = [:]
    private var thread: Thread?
    private let finished = DispatchSemaphore(value: 0)

    private var backup: [CameraSetting: String] = [:]
    private var focusBackup: String?
    private var focusMoved = false

    init() {
        targetOverrides = overrides
    }

    func start() {
        guard thread == nil else { return }
        withLock { stopRequested = false }
        let thread = Thread { [weak self] in self?.run() }
        thread.name = "Fujiyoshida capture"
        thread.qualityOfService = .userInteractive
        self.thread = thread
        thread.start()
    }

    func stopAndWait(timeout: TimeInterval = 3) {
        guard thread != nil else { return }
        withLock { stopRequested = true }
        _ = finished.wait(timeout: .now() + timeout)
    }

    func setPaused(_ paused: Bool) {
        isPaused = paused
        withLock { pausedFlag = paused }
    }

    func value(for setting: CameraSetting) -> String? {
        overrides[setting]
    }

    func setOverride(_ setting: CameraSetting, to value: String?) {
        var changed = [setting]
        overrides[setting] = value
        if setting == .whiteBalance, overrides[.colorTemperature] != nil {
            overrides[.colorTemperature] = nil
            changed.append(.colorTemperature)
        }
        if setting == .colorTemperature {
            overrides[.whiteBalance] = value == nil ? nil : CameraSetting.colorTemperatureMode
            changed.insert(.whiteBalance, at: 0)
        }
        CameraSettingsStore.save(overrides: overrides)
        let snapshot = overrides
        withLock {
            targetOverrides = snapshot
            commands.append(.apply(changed))
        }
    }

    func setRotation(_ degrees: Int) {
        rotation = degrees
        UserDefaults.standard.set(degrees, forKey: "rotation")
        withLock { rotationFlag = degrees }
    }

    func setFocusPoint(_ point: CameraInfo.FocusPoint) {
        withLock {
            commands.removeAll { if case .focusArea = $0 { return true } else { return false } }
            commands.append(.focusArea(point.value))
        }
    }

    func focusNow() {
        withLock { commands.append(.focusNow) }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }

    private var shouldStop: Bool { withLock { stopRequested } }

    private func run() {
        let camera = FujiCamera()
        let converter = FrameConverter()
        let sink = SinkFeeder()
        let statusFrames = StatusFrameRenderer()
        let decodeQueue = DispatchQueue(label: "fujiyoshida.decode", qos: .userInteractive)
        let decodeSlots = DispatchSemaphore(value: 2)
        let preview = self.preview
        var frameCount = 0
        var cameraTime: TimeInterval = 0
        var windowStart = Date()
        var lastInfoRead = Date.distantPast
        var lastFaceRead = Date.distantPast
        var info = CameraInfo()
        var lastViewerCheck = Date.distantPast
        var viewerActive = false
        var failures = 0
        var streaming = false

        func idle(_ seconds: TimeInterval, showing frame: StatusFrame? = nil) {
            let deadline = Date().addingTimeInterval(seconds)
            repeat {
                if let frame, viewerActive, let buffer = statusFrames.buffer(for: frame) { sink.send(buffer) }
                Thread.sleep(forTimeInterval: 0.2)
            } while !shouldStop && Date() < deadline
        }

        while !shouldStop {
            guard sink.connect() else {
                publish("Waiting for camera extension…", state: .waitingForExtension)
                idle(1)
                continue
            }

            if Date().timeIntervalSince(lastViewerCheck) >= 0.5 {
                lastViewerCheck = Date()
                viewerActive = sink.isViewerActive()
            }

            let paused = withLock { pausedFlag }
            if paused || !(viewerActive || preview.isActive) {
                if camera.isConnected { endSession(camera) }
                streaming = false
                failures = 0
                publishInfo(nil)
                if paused {
                    publish("Paused", state: .paused)
                    idle(0.4, showing: .paused)
                } else {
                    publish("Standby – starts when an app uses the camera", state: .standby)
                    idle(0.4)
                }
                continue
            }

            if !camera.isConnected {
                if failures == 0 { publish("Starting camera…", state: .connecting) }
                if viewerActive, let buffer = statusFrames.buffer(for: failures == 0 ? .starting : .stuck) { sink.send(buffer) }
                do {
                    try camera.connect()
                    beginSession(camera)
                } catch {
                    publish("No camera – connect the X-T4 in USB Tether Shooting mode", state: .noCamera)
                    idle(2, showing: .noCamera)
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
                    publish("Streaming from \(camera.modelName)", state: .streaming)
                }

                if decodeSlots.wait(timeout: .now()) == .success {
                    let rotation = withLock { rotationFlag }
                    decodeQueue.async {
                        autoreleasepool {
                            if let buffer = converter.pixelBuffer(fromJPEG: jpeg, rotation: rotation) {
                                sink.send(buffer)
                                preview.show(buffer)
                            }
                        }
                        decodeSlots.signal()
                    }
                }

                runCommands(on: camera)

                if Date().timeIntervalSince(lastInfoRead) >= 0.25 {
                    lastInfoRead = Date()
                    var settings = camera.readSettings(CameraInfo.settingNames)
                    settings[CameraInfo.focusPointKey] = camera.readPropertyString(Self.currentFocusProperty)
                    info = CameraInfo(settings: settings)
                    info.power = CameraInfo.Power(code: camera.readPropertyUInt32(Self.batteryStateProperty))
                    info.detection = CameraInfo.Detection(
                        face: camera.readPropertyUInt16(FujiCamera.faceDetectionProperty),
                        eye: camera.readPropertyUInt16(FujiCamera.eyeDetectionProperty)
                    )
                }
                if Date().timeIntervalSince(lastFaceRead) >= 0.1 {
                    lastFaceRead = Date()
                    let frameWidth = converter.sourceSize.width
                    info.faces = info.detection == .off ? [] : camera.readFaceFrames().compactMap { CameraInfo.Face($0, frameWidth: frameWidth) }
                    publishInfo(info, region: converter.visibleRegion)
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
                publish("Camera not sending live view – close camera menus or switch it off and on", state: .stuck)
                publishInfo(nil)
                camera.disconnect()
                idle(min(Double(failures), 5), showing: .stuck)
            }
        }

        decodeQueue.sync {}
        if camera.isConnected { endSession(camera) }
        sink.disconnect()
        finished.signal()
        DispatchQueue.main.async {
            self.thread = nil
            self.live.info = nil
            self.live.rate = ""
        }
    }

    private func beginSession(_ camera: FujiCamera) {
        let cameraChoices = Dictionary(uniqueKeysWithValues: CameraSetting.allCases.map { ($0, camera.availableValues(for: $0)) })
            .filter { !$0.value.isEmpty }
        if !cameraChoices.isEmpty {
            CameraSettingsStore.save(choices: cameraChoices)
            DispatchQueue.main.async { if self.choices != cameraChoices { self.choices = cameraChoices } }
        }

        if backup.isEmpty {
            backup = Dictionary(uniqueKeysWithValues: CameraSetting.allCases.compactMap { setting in camera.currentValue(of: setting).map { (setting, $0) } })
            focusBackup = camera.readPropertyString(Self.focusAreaProperty)
            focusMoved = false
        }

        let targets = withLock { targetOverrides }
        apply(CameraSetting.allCases.filter { targets[$0] != nil }, targets: targets, on: camera)
    }

    private func endSession(_ camera: FujiCamera) {
        camera.stopLiveView()
        let targets = withLock { targetOverrides }
        for setting in CameraSetting.allCases where targets[setting] != nil {
            if let original = backup[setting] { _ = camera.apply(original, to: setting) }
        }
        if focusMoved, let focusBackup { camera.writePropertyString(Self.focusAreaProperty, focusBackup) }
        backup = [:]
        focusBackup = nil
        focusMoved = false
        camera.disconnect()
    }

    private func runCommands(on camera: FujiCamera) {
        let pending: ([Command], [CameraSetting: String]) = withLock {
            defer { commands.removeAll() }
            return (commands, targetOverrides)
        }
        for command in pending.0 {
            switch command {
            case .apply(let settings):
                camera.stopLiveView()
                apply(settings, targets: pending.1, on: camera)
            case .focusArea(let value):
                focusMoved = true
                if !writeWithRetry({ camera.writePropertyString(Self.focusAreaProperty, value) }) {
                    showMessage("Camera kept its focus point")
                }
            case .focusNow:
                do { try camera.focusNow() } catch { showMessage("Camera couldn't focus") }
            }
        }
    }

    private func apply(_ settings: [CameraSetting], targets: [CameraSetting: String], on camera: FujiCamera) {
        var rejected: CameraSetting?
        for setting in CameraSetting.allCases where settings.contains(setting) {
            guard let value = targets[setting] ?? backup[setting] else { continue }
            let accepted = camera.apply(value, to: setting)
            if !accepted, targets[setting] != nil, rejected == nil { rejected = setting }
        }
        if let rejected { showMessage(rejected.rejectionHint) }
    }

    private func writeWithRetry(_ write: () -> Bool) -> Bool {
        for attempt in 0..<5 {
            if write() { return true }
            if attempt < 4 { Thread.sleep(forTimeInterval: 0.05) }
        }
        return false
    }

    private func publish(_ status: String, state: State) {
        DispatchQueue.main.async {
            if self.status != status { self.status = status }
            if self.state != state { self.state = state }
            if state == .noCamera, self.batteryLevel != nil { self.batteryLevel = nil }
            if state != .streaming, !self.live.rate.isEmpty { self.live.rate = "" }
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
            if let info, info.power != .unknown {
                let level = info.power == .battery ? info.batteryLevel : nil
                if self.batteryLevel != level { self.batteryLevel = level }
            }
            if let region, self.live.visibleRegion != region { self.live.visibleRegion = region }
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
}
