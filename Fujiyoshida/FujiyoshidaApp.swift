import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let capture = CaptureController()
    let installer = ExtensionInstaller()
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installer.activate()
        capture.start()
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { NSApp.terminate(nil) }
        source.resume()
        terminationSignal = source
    }

    func applicationWillTerminate(_ notification: Notification) {
        capture.stopAndWait()
    }
}

@main
struct FujiyoshidaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(capture: appDelegate.capture, installer: appDelegate.installer)
        } label: {
            MenuIcon(capture: appDelegate.capture, installer: appDelegate.installer)
        }

        Window("Fujiyoshida Preview", id: "preview") {
            PreviewWindow(capture: appDelegate.capture)
        }
        .windowLevel(.floating)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 400, height: 330)
        .defaultLaunchBehavior(.suppressed)
    }
}

private struct MenuContent: View {
    @ObservedObject var capture: CaptureController
    @ObservedObject var installer: ExtensionInstaller
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(capture.status)
        if capture.isBatteryLow, let level = capture.batteryLevel {
            Text("Camera battery low – \(level)%")
        }
        if installer.needsAttention {
            Text(installer.status)
        }
        Divider()
        Button("Show Preview") {
            openWindow(id: "preview")
            NSApp.activate()
        }
        .keyboardShortcut("p")
        FocusButton(capture: capture)
        Divider()
        CameraControls(capture: capture)
        Divider()
        Button(capture.isPaused ? "Resume Camera" : "Pause Camera") {
            capture.setPaused(!capture.isPaused)
        }
        Menu("Camera Extension") {
            Button("Reinstall") { installer.activate() }
            Button("Uninstall") { installer.deactivate() }
        }
        Divider()
        Button("Quit Fujiyoshida") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct FocusButton: View {
    @ObservedObject var capture: CaptureController

    var body: some View {
        Button("Focus Now") { capture.focusNow() }
            .keyboardShortcut("f")
            .disabled(!capture.isStreaming)
    }
}

struct CameraControls: View {
    @ObservedObject var capture: CaptureController
    private static let focusSettings: [CameraSetting] = [.focusMode, .focusArea, .faceDetection]

    var body: some View {
        SettingPicker(capture: capture, setting: .filmSimulation)
        Menu(CameraSetting.whiteBalance.title) {
            SettingOptions(capture: capture, setting: .whiteBalance)
            Divider()
            Menu(CameraSetting.colorTemperature.title) {
                SettingOptions(capture: capture, setting: .colorTemperature, includesCameraSetting: false)
            }
        }
        .disabled(options(for: .whiteBalance).isEmpty)
        SettingPicker(capture: capture, setting: .shutterSpeed)
        SettingPicker(capture: capture, setting: .iso)
        Menu("Focus") {
            ForEach(Self.focusSettings, id: \.self) { setting in
                Section(setting.title) {
                    SettingOptions(capture: capture, setting: setting, includesCameraSetting: false)
                }
            }
            Divider()
            Button("Use Camera Settings") {
                Self.focusSettings.forEach { capture.setOverride($0, to: nil) }
            }
            .disabled(Self.focusSettings.allSatisfy { capture.value(for: $0) == nil })
        }
        .disabled(options(for: .focusMode).isEmpty)
        RotationPicker(capture: capture)
    }

    private func options(for setting: CameraSetting) -> [String] {
        setting.options(from: capture.choices[setting] ?? [])
    }
}

private struct RotationPicker: View {
    @ObservedObject var capture: CaptureController

    var body: some View {
        Menu("Rotation") {
            Picker("Rotation", selection: Binding(get: { capture.rotation }, set: { capture.setRotation($0) })) {
                Text("Landscape").tag(0)
                Text("Portrait, Rotate Right").tag(90)
                Text("Portrait, Rotate Left").tag(270)
                Text("Upside Down").tag(180)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }
}

private struct SettingPicker: View {
    @ObservedObject var capture: CaptureController
    let setting: CameraSetting

    var body: some View {
        Menu(setting.title) {
            SettingOptions(capture: capture, setting: setting)
        }
        .disabled(setting.options(from: capture.choices[setting] ?? []).isEmpty)
    }
}

private struct SettingOptions: View {
    @ObservedObject var capture: CaptureController
    let setting: CameraSetting
    var includesCameraSetting = true

    var body: some View {
        Picker(setting.title, selection: selection) {
            if includesCameraSetting {
                Text("Camera Setting").tag(String?.none)
                Divider()
            }
            ForEach(setting.options(from: capture.choices[setting] ?? []), id: \.self) { value in
                Text(setting.label(for: value)).tag(String?.some(value))
            }
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private var selection: Binding<String?> {
        Binding(
            get: { capture.value(for: setting) },
            set: { capture.setOverride(setting, to: $0) }
        )
    }
}

private struct MenuIcon: View {
    @ObservedObject var capture: CaptureController
    @ObservedObject var installer: ExtensionInstaller

    var body: some View {
        if capture.isBatteryLow, let level = capture.batteryLevel {
            Label("\(level)%", systemImage: CameraInfo.batterySymbol(for: level))
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("Camera battery low, \(level) percent")
        } else {
            Image(systemName: symbol)
                .accessibilityLabel(capture.status)
        }
    }

    private var symbol: String {
        if installer.needsAttention { return "puzzlepiece.extension" }
        switch capture.state {
        case .streaming: return "video.fill"
        case .connecting: return "video.badge.ellipsis"
        case .standby: return "video"
        case .noCamera: return "video.slash"
        case .stuck: return "exclamationmark.triangle"
        case .waitingForExtension: return "puzzlepiece.extension"
        case .paused: return "pause.circle"
        }
    }
}
