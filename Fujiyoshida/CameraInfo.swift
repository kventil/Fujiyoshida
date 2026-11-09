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

        var center: CGPoint {
            CGPoint(
                x: (Double(column + columns / 2) + 0.5) / Double(columns),
                y: (Double(row + rows / 2) + 0.5) / Double(rows)
            )
        }

        var boxSize: CGSize {
            CGSize(width: Double(size) / Double(columns), height: Double(size) / Double(rows))
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
    var shotsRemaining = ""
    var focusPoint: FocusPoint?

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
        battery = Self.battery(settings["d36b"])
        shotsRemaining = settings["availableshots"] ?? ""
        focusPoint = Self.focusPoint(settings[Self.focusPointKey], grid: settings["focuspoints"])
    }

    var exposureSummary: String {
        [exposureMode, shutterSpeed, aperture, iso.isEmpty ? "" : "ISO \(iso)", exposureCompensation]
            .filter { !$0.isEmpty }
            .joined(separator: "  ")
    }

    var focusSummary: String {
        [focusMode, focusArea].filter { !$0.isEmpty }.joined(separator: " · ")
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
        return FocusPoint(column: values[0], row: values[1], size: values.count > 2 ? max(values[2], 1) : 2, columns: columns, rows: rows)
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
        case "Multi-area AF": return "Wide/Tracking"
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

    private static func battery(_ raw: String?) -> String {
        guard let first = raw?.split(separator: ",").first, let value = Int(first) else { return "" }
        return "\(value)%"
    }
}
