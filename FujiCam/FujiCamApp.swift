import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let capture = CaptureController()
    private var terminationSignal: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
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
struct FujiCamApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var installer = ExtensionInstaller()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(capture: appDelegate.capture, installer: installer)
        } label: {
            MenuIcon(capture: appDelegate.capture, installer: installer)
        }

        Window("FujiCam Preview", id: "preview") {
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
        if let message = capture.message {
            Text(message)
        }
        Text(installer.status)
        Divider()
        ExposureMenu(capture: capture)
        Divider()
        Button("Show Preview") {
            openWindow(id: "preview")
            NSApp.activate()
        }
        .keyboardShortcut("p")
        Button(capture.isRunning ? "Stop Live View" : "Start Live View") {
            capture.isRunning ? capture.stop() : capture.start()
        }
        Divider()
        Button("Install Camera Extension") { installer.activate() }
        Button("Uninstall Camera Extension") { installer.deactivate() }
        Divider()
        Button("Quit FujiCam") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

struct ExposureMenu: View {
    @ObservedObject var capture: CaptureController

    var body: some View {
        Button("Shutter \(CaptureController.shutterForFrameRate) (2× frame rate)") {
            capture.setShutterForFrameRate()
        }
        .disabled(!capture.isStreaming)
        Menu("ISO") {
            Button("Auto") { capture.setISO("-1") }
            Divider()
            ForEach(capture.isoChoices, id: \.self) { value in
                Button(value) { capture.setISO(value) }
            }
        }
        .disabled(!capture.isStreaming || capture.isoChoices.isEmpty)
    }
}

private struct MenuIcon: View {
    @ObservedObject var capture: CaptureController
    @ObservedObject var installer: ExtensionInstaller

    var body: some View {
        Image(systemName: capture.isStreaming ? "camera.fill" : "camera")
            .task {
                installer.activate()
                capture.start()
            }
    }
}
