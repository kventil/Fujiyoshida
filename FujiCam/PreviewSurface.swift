import AppKit
import CoreVideo
import QuartzCore
import SwiftUI

final class PreviewSurface {
    let layer: CALayer = {
        let layer = CALayer()
        layer.contentsGravity = .resizeAspect
        layer.backgroundColor = NSColor.black.cgColor
        return layer
    }()

    private let lock = NSLock()
    private var active = false
    private var current: CVPixelBuffer?

    var isActive: Bool {
        get { lock.lock(); defer { lock.unlock() }; return active }
        set {
            lock.lock(); active = newValue; lock.unlock()
            if !newValue {
                DispatchQueue.main.async {
                    self.layer.contents = nil
                    self.current = nil
                }
            }
        }
    }

    func show(_ buffer: CVPixelBuffer) {
        guard isActive, let surface = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else { return }
        DispatchQueue.main.async {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            self.layer.contents = surface
            CATransaction.commit()
            self.current = buffer
        }
    }
}

struct PreviewLayerView: NSViewRepresentable {
    let surface: PreviewSurface

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.addSublayer(surface.layer)
        view.postsFrameChangedNotifications = true
        context.coordinator.observe(view, layer: surface.layer)
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        surface.layer.frame = view.bounds
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        private var token: NSObjectProtocol?

        func observe(_ view: NSView, layer: CALayer) {
            token = NotificationCenter.default.addObserver(
                forName: NSView.frameDidChangeNotification, object: view, queue: .main
            ) { _ in
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                layer.frame = view.bounds
                CATransaction.commit()
            }
        }

        deinit {
            if let token { NotificationCenter.default.removeObserver(token) }
        }
    }
}
