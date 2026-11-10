import CoreGraphics
import Foundation

struct CameraInfo: Equatable {
    enum FocusState: Equatable {
        case idle, focused, failed
    }

    struct FocusPoint: Equatable {
        var column: Int
        var row: Int
        var size: Int
        var columns: Int
        var rows: Int

        var span: Int { size > 17 ? 2 * (size - 17) + 1 : 1 }

        var center: CGPoint {
            CGPoint(
                x: (Double(column + columns / 2) + 0.5) / Double(columns),
                y: (Double(row + rows / 2) + 0.5) / Double(rows)
            )
        }

        var boxSize: CGSize {
            CGSize(width: Double(span) / Double(columns), height: Double(span) / Double(rows))
        }

        var value: String { "\(column),\(row),\(size)" }

        func moved(to location: CGPoint) -> FocusPoint {
            var point = self
            point.column = Self.offset(location.x, cells: columns, span: span)
            point.row = Self.offset(location.y, cells: rows, span: span)
            return point
        }

        private static func offset(_ position: Double, cells: Int, span: Int) -> Int {
            let limit = max(cells / 2 - span / 2, 0)
            let cell = Int((position * Double(cells)).rounded(.down)) - cells / 2
            return min(max(cell, -limit), limit)
        }
    }

    struct Face: Equatable {
        var rect: CGRect
        var red: Double
        var green: Double
        var blue: Double
        var isSelected: Bool

        init?(_ raw: String, frameWidth: CGFloat) {
            let values = raw.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard values.count >= 14, values[12] != 0, frameWidth > 0 else { return nil }
            rect = CGRect(
                x: Double(values[2]) / frameWidth,
                y: Double(values[3]) / frameWidth,
                width: Double(values[4]) / frameWidth,
                height: Double(values[5]) / frameWidth
            )
            red = Double(values[6]) / 255
            green = Double(values[7]) / 255
            blue = Double(values[8]) / 255
            isSelected = values[13] == 2
        }
    }

    enum Detection: Equatable {
        case off, face, faceAndEye(String)

        init(face: UInt16?, eye: UInt16?) {
            guard face == 1 else { self = .off; return }
            switch eye {
            case 2: self = .faceAndEye("Eye auto")
            case 3: self = .faceAndEye("Right eye")
            case 4: self = .faceAndEye("Left eye")
            default: self = .face
            }
        }

        var label: String {
            switch self {
            case .off: return ""
            case .face: return "Face"
            case .faceAndEye(let eye): return "Face · \(eye)"
            }
        }
    }

    enum Power: Equatable {
        case unknown, battery, usb, charging

        init(code: UInt32?) {
            guard let code else { self = .unknown; return }
            switch code {
            case 7: self = .usb
            case 8...11: self = .charging
            default: self = .battery
            }
        }
    }

    static let focusPointKey = "focuspoint"

    var exposureMode = ""
    var shutterSpeed = ""
    var aperture = ""
    var iso = ""
    var exposureCompensation = ""
    var focusMode = ""
    var focusArea = ""
    var focusState = FocusState.idle
    var filmSimulation = ""
    var whiteBalance = ""
    var lens = ""
    var battery = ""
    var batteryLevel: Int?
    var power = Power.unknown
    var shotsRemaining = ""
    var focusPoint: FocusPoint?
    var faces: [Face] = []
    var detection = Detection.off

    static let settingNames = [
        "expprogram", "shutterspeed", "f-number", "iso", "exposurecompensation",
        "focusmode", "focusmetermode", "d209", "filmsimulation", "whitebalance",
        "lensname", "d36b", "availableshots", "focuspoints",
    ]

    init() {}

    static let placeholder: CameraInfo = {
        var info = CameraInfo()
        info.exposureMode = "–"
        info.shutterSpeed = "–"
        info.aperture = "–"
        info.iso = "–"
        info.focusMode = "–"
        info.filmSimulation = "–"
        info.battery = "–"
        info.shotsRemaining = "–"
        info.lens = "No camera"
        return info
    }()

    init(settings: [String: String]) {
        exposureMode = settings["expprogram"] ?? ""
        shutterSpeed = settings["shutterspeed"] ?? ""
        aperture = settings["f-number"] ?? ""
        iso = Self.iso(settings["iso"])
        exposureCompensation = Self.exposureCompensation(settings["exposurecompensation"])
        focusMode = Self.focusMode(settings["focusmode"])
        focusArea = Self.focusArea(settings["focusmetermode"])
        focusState = Self.focusState(settings["d209"])
        filmSimulation = settings["filmsimulation"] ?? ""
        whiteBalance = Self.whiteBalance(settings["whitebalance"])
        lens = Self.lens(settings["lensname"])
        batteryLevel = Self.batteryLevel(settings["d36b"])
        battery = batteryLevel.map { "\($0)%" } ?? ""
        shotsRemaining = settings["availableshots"] ?? ""
        focusPoint = Self.focusPoint(settings[Self.focusPointKey], grid: settings["focuspoints"])
    }

    var exposureSummary: String {
        [exposureMode, shutterSpeed, aperture, iso.isEmpty ? "" : "ISO \(iso)", exposureCompensation]
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
    }

    var focusSummary: String {
        [focusMode, focusArea, detection.label].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var styleSummary: String {
        [filmSimulation, whiteBalance].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private static func focusPoint(_ raw: String?, grid: String?) -> FocusPoint? {
        guard let values = raw?.split(separator: ",").compactMap({ Int($0) }), values.count >= 2 else { return nil }
        var rows = 17, columns = 25
        if let grid, let open = grid.firstIndex(of: "("), let close = grid.firstIndex(of: ")") {
            let dims = grid[grid.index(after: open)..<close].split(separator: "x").compactMap { Int($0) }
            if dims.count == 2 { rows = dims[0]; columns = dims[1] }
        }
        return FocusPoint(column: values[0], row: values[1], size: values.count > 2 ? values[2] : 1, columns: columns, rows: rows)
    }

    private static func iso(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        guard let value = Int(raw) else { return raw }
        return value < 0 ? "Auto" : String(value)
    }

    private static func exposureCompensation(_ raw: String?) -> String {
        guard let raw, let value = Double(raw) else { return "" }
        let rounded = (value * 10).rounded() / 10
        if rounded == 0 { return "±0 EV" }
        return String(format: "%@%.1f EV", rounded > 0 ? "+" : "−", abs(rounded))
    }

    private static func focusMode(_ raw: String?) -> String {
        switch raw {
        case "Continuous-Servo AF": return "AF-C"
        case "Single-Servo AF": return "AF-S"
        case "Manual": return "MF"
        default: return raw ?? ""
        }
    }

    private static func focusArea(_ raw: String?) -> String {
        switch raw {
        case "Single-area AF": return "Single point"
        case "Dynamic-area AF": return "Zone"
        case "Group-dynamic AF", "Multi-area AF": return "Wide/Tracking"
        default: return raw ?? ""
        }
    }

    private static func focusState(_ raw: String?) -> FocusState {
        switch raw {
        case "2": return .focused
        case "3": return .failed
        default: return .idle
        }
    }

    private static func whiteBalance(_ raw: String?) -> String {
        raw == "Automatic" ? "AWB" : (raw ?? "")
    }

    private static func lens(_ raw: String?) -> String {
        guard let raw else { return "" }
        let parts = raw.split(separator: ",").map(String.init)
        return parts.count >= 2 ? parts[1] : raw
    }

    private static func batteryLevel(_ raw: String?) -> Int? {
        guard let first = raw?.split(separator: ",").first else { return nil }
        return Int(first)
    }

    static let lowBatteryLevel = 20

    var batteryText: String {
        switch power {
        case .usb: return "USB power"
        case .charging: return "Charging"
        case .battery, .unknown: return battery
        }
    }

    var batteryIcon: String {
        switch power {
        case .usb: return "powerplug"
        case .charging: return "battery.100percent.bolt"
        case .battery, .unknown: return Self.batterySymbol(for: batteryLevel)
        }
    }

    var isBatteryLow: Bool {
        power == .battery && (batteryLevel ?? 100) < Self.lowBatteryLevel
    }

    static func batterySymbol(for level: Int?) -> String {
        guard let level else { return "battery.0percent" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
