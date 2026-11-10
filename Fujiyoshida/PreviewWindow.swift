import SwiftUI

struct PreviewWindow: View {
    @ObservedObject var capture: CaptureController
    @ObservedObject var live: LiveStats

    init(capture: CaptureController) {
        self.capture = capture
        self.live = capture.live
    }

    var body: some View {
        VStack(spacing: 0) {
            PreviewLayerView(surface: capture.preview)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .overlay {
                    if capture.isStreaming, capture.rotation == 0, let info = live.info, !info.faces.isEmpty {
                        FaceBoxes(faces: info.faces, region: live.visibleRegion)
                    }
                }
                .overlay {
                    if capture.isStreaming, capture.rotation == 0, let info = live.info, let point = info.focusPoint {
                        FocusBox(point: point, state: info.focusState, region: live.visibleRegion)
                        FocusTarget(region: live.visibleRegion) { location in
                            capture.setFocusPoint(point.moved(to: location))
                        }
                    }
                }
                .overlay {
                    if !capture.isStreaming {
                        NoPictureView(status: capture.status)
                    }
                }
                .overlay(alignment: .bottom) {
                    if let message = live.message {
                        Text(message)
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.regularMaterial, in: Capsule())
                            .padding(8)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: live.message)
            CameraInfoBar(info: capture.isStreaming ? live.info : nil, rate: live.rate)
        }
        .contextMenu {
            FocusButton(capture: capture)
            Divider()
            CameraControls(capture: capture)
        }
        .frame(minWidth: 320, idealWidth: 400)
        .onAppear { capture.preview.isActive = true }
        .onDisappear { capture.preview.isActive = false }
    }
}

private struct NoPictureView: View {
    let status: String

    var body: some View {
        ZStack {
            Color.black
            VStack(spacing: 10) {
                Image(systemName: "camera.badge.ellipsis")
                    .font(.system(size: 32))
                Text(status)
                    .font(.callout)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
            }
            .foregroundStyle(.secondary)
            .padding()
        }
    }
}

private struct CameraInfoBar: View {
    let info: CameraInfo?
    let rate: String

    var body: some View {
        let shown = info ?? .placeholder
        VStack(alignment: .leading, spacing: 4) {
            Text(shown.exposureSummary)
                .font(.system(.body, design: .monospaced).weight(.medium))
            HStack(spacing: 6) {
                FocusIndicator(state: shown.focusState)
                Text(shown.focusSummary)
                Spacer()
                Label(shown.batteryText, systemImage: shown.batteryIcon)
                    .foregroundStyle(shown.isBatteryLow ? Color.red : Color.primary)
            }
            HStack {
                Text(shown.styleSummary)
                Spacer()
                Text("\(shown.shotsRemaining) shots")
            }
            .foregroundStyle(.secondary)
            HStack {
                Text(shown.lens)
                Spacer()
                Text(info == nil ? "–" : rate)
            }
            .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .opacity(info == nil ? 0.5 : 1)
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

private struct FaceBoxes: View {
    let faces: [CameraInfo.Face]
    let region: CGRect

    var body: some View {
        GeometryReader { geometry in
            ForEach(faces.indices, id: \.self) { index in
                let face = faces[index]
                let rect = CGRect(
                    x: (face.rect.minX - region.minX) / region.width * geometry.size.width,
                    y: (face.rect.minY - region.minY) / region.height * geometry.size.height,
                    width: face.rect.width / region.width * geometry.size.width,
                    height: face.rect.height / region.height * geometry.size.height
                )
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(red: face.red, green: face.green, blue: face.blue), lineWidth: face.isSelected ? 2 : 1)
                    .shadow(color: .black.opacity(0.5), radius: 1)
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
            }
            .animation(.easeOut(duration: 0.1), value: faces)
        }
        .allowsHitTesting(false)
    }
}

private struct FocusTarget: View {
    let region: CGRect
    let select: (CGPoint) -> Void

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture { location in
                    select(CGPoint(
                        x: region.minX + location.x / geometry.size.width * region.width,
                        y: region.minY + location.y / geometry.size.height * region.height
                    ))
                }
        }
        .help("Click to move the focus point")
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
