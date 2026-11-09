import SwiftUI

struct PreviewWindow: View {
    @ObservedObject var capture: CaptureController

    var body: some View {
        VStack(spacing: 0) {
            PreviewLayerView(surface: capture.preview)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    if capture.isStreaming, let info = capture.info, let point = info.focusPoint {
                        FocusBox(point: point, state: info.focusState, region: capture.visibleRegion)
                    }
                }
                .overlay(alignment: .center) {
                    if !capture.isStreaming {
                        Text(capture.status)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding()
                    }
                }
            CameraInfoBar(info: capture.info)
            if let message = capture.message {
                Text(message)
                    .font(.caption)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.bar)
            }
        }
        .contextMenu { ExposureMenu(capture: capture) }
        .frame(minWidth: 320, idealWidth: 400)
        .onAppear { capture.preview.isActive = true }
        .onDisappear { capture.preview.isActive = false }
    }
}

private struct CameraInfoBar: View {
    let info: CameraInfo?

    var body: some View {
        if let info {
            VStack(alignment: .leading, spacing: 4) {
                Text(info.exposureSummary)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                HStack(spacing: 6) {
                    FocusIndicator(state: info.focusState)
                    Text(info.focusSummary)
                    Spacer()
                    if !info.battery.isEmpty {
                        Label(info.battery, systemImage: "battery.75percent")
                    }
                }
                HStack {
                    Text(info.styleSummary)
                    Spacer()
                    if !info.shotsRemaining.isEmpty {
                        Text("\(info.shotsRemaining) shots")
                    }
                }
                .foregroundStyle(.secondary)
                if !info.lens.isEmpty {
                    Text(info.lens)
                        .foregroundStyle(.secondary)
                }
            }
            .font(.caption)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.bar)
        }
    }
}

private struct FocusBox: View {
    let point: CameraInfo.FocusPoint
    let state: CameraInfo.FocusState
    let region: CGRect

    var body: some View {
        GeometryReader { geometry in
            let center = point.center
            let box = point.boxSize
            let x = (center.x - region.minX) / region.width * geometry.size.width
            let y = (center.y - region.minY) / region.height * geometry.size.height
            let width = box.width / region.width * geometry.size.width
            let height = box.height / region.height * geometry.size.height
            FocusBrackets()
                .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .shadow(color: .black.opacity(0.6), radius: 1)
                .frame(width: width, height: height)
                .position(x: x, y: y)
                .animation(.easeOut(duration: 0.15), value: point)
        }
        .allowsHitTesting(false)
    }

    private var color: Color {
        switch state {
        case .focused: return .green
        case .failed: return .red
        case .idle: return .white
        }
    }
}

private struct FocusBrackets: Shape {
    func path(in rect: CGRect) -> Path {
        let arm = min(rect.width, rect.height) * 0.25
        var path = Path()
        for (corner, dx, dy) in [
            (CGPoint(x: rect.minX, y: rect.minY), 1.0, 1.0),
            (CGPoint(x: rect.maxX, y: rect.minY), -1.0, 1.0),
            (CGPoint(x: rect.minX, y: rect.maxY), 1.0, -1.0),
            (CGPoint(x: rect.maxX, y: rect.maxY), -1.0, -1.0),
        ] {
            path.move(to: CGPoint(x: corner.x + arm * dx, y: corner.y))
            path.addLine(to: corner)
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + arm * dy))
        }
        return path
    }
}

private struct FocusIndicator: View {
    let state: CameraInfo.FocusState

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(help)
    }

    private var color: Color {
        switch state {
        case .focused: return .green
        case .failed: return .red
        case .idle: return .gray
        }
    }

    private var help: String {
        switch state {
        case .focused: return "In focus"
        case .failed: return "Focus failed"
        case .idle: return "Not focusing"
        }
    }
}
