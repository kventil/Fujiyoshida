import Foundation

enum CameraSetting: String, CaseIterable {
    case whiteBalance = "whitebalance"
    case colorTemperature = "colortemperature"
    case filmSimulation = "filmsimulation"
    case shutterSpeed = "shutterspeed"
    case iso
    case focusMode = "focusmode"
    case focusArea = "focusmetermode"
    case faceDetection = "facedetection"

    static let colorTemperatureMode = "Choose Color Temperature"

    var title: String {
        switch self {
        case .filmSimulation: return "Film Simulation"
        case .whiteBalance: return "White Balance"
        case .colorTemperature: return "Color Temperature"
        case .shutterSpeed: return "Shutter"
        case .iso: return "ISO"
        case .focusMode: return "AF Mode"
        case .focusArea: return "AF Area"
        case .faceDetection: return "Face/Eye Detection"
        }
    }

    var rejectionHint: String {
        switch self {
        case .shutterSpeed: return "Camera kept its shutter speed – set the shutter dial to T"
        case .iso: return "Camera kept its ISO – set the ISO dial to A"
        case .focusArea: return "Camera kept its AF area – Zone and Wide/Tracking need AF-S or AF-C"
        case .focusMode: return "Camera kept its AF mode"
        case .faceDetection: return "Camera kept its face/eye detection"
        default: return "Camera kept its \(title.lowercased())"
        }
    }

    func label(for value: String) -> String {
        switch self {
        case .iso:
            guard let number = Int(value), number < 0 else { return value }
            return number == -1 ? "Auto" : "Auto \(-number)"
        case .shutterSpeed:
            return value == Self.smoothShutter ? "\(value)  (2× frame rate)" : value
        case .colorTemperature:
            return "\(value) K"
        case .filmSimulation:
            return value.trimmingCharacters(in: CharacterSet(charactersIn: ", "))
        case .whiteBalance:
            return value
        case .focusMode:
            return ["Manual": "MF", "Single-Servo AF": "AF-S", "Continuous-Servo AF": "AF-C"][value] ?? value
        case .focusArea:
            return ["Single-area AF": "Single Point", "Dynamic-area AF": "Zone", "Group-dynamic AF": "Wide/Tracking"][value] ?? value
        case .faceDetection:
            return FaceDetectionMode(rawValue: value)?.label ?? value
        }
    }

    func options(from cameraChoices: [String]) -> [String] {
        switch self {
        case .filmSimulation:
            return cameraChoices
        case .whiteBalance:
            return cameraChoices.filter { !$0.hasPrefix("Unknown") && $0 != Self.colorTemperatureMode }
        case .colorTemperature:
            let curated = ["2500", "3000", "3200", "4000", "4500", "5000", "5600", "6000", "6500", "7500", "10000"]
            return cameraChoices.isEmpty ? curated : curated.filter(cameraChoices.contains)
        case .shutterSpeed:
            let curated = ["1/30", "1/50", "1/60", "1/100", "1/125", "1/250", "1/500", "1/1000"]
            return curated.filter(cameraChoices.contains)
        case .focusMode:
            return ["Single-Servo AF", "Continuous-Servo AF", "Manual"].filter(cameraChoices.contains)
        case .focusArea, .faceDetection:
            return cameraChoices
        case .iso:
            let autos = cameraChoices.filter { (Int($0) ?? 0) < 0 }.sorted { (Int($0) ?? 0) > (Int($1) ?? 0) }
            return autos + cameraChoices.filter { (Int($0) ?? 0) > 0 }
        }
    }

    static var smoothShutter: String { "1/\(Int(FujiyoshidaConfig.frameRate) * 2)" }
}

enum FaceDetectionMode: String, CaseIterable {
    case off, face, eyeAuto, rightEye, leftEye

    var label: String {
        switch self {
        case .off: return "Off"
        case .face: return "Face"
        case .eyeAuto: return "Face + Eye Auto"
        case .rightEye: return "Face + Right Eye"
        case .leftEye: return "Face + Left Eye"
        }
    }

    var propertyValues: (face: UInt16, eye: UInt16) {
        switch self {
        case .off: return (2, 1)
        case .face: return (1, 1)
        case .eyeAuto: return (1, 2)
        case .rightEye: return (1, 3)
        case .leftEye: return (1, 4)
        }
    }

    init?(face: UInt16, eye: UInt16) {
        guard let mode = Self.allCases.first(where: { $0.propertyValues == (face, eye) || (face == 2 && $0 == .off) }) else { return nil }
        self = mode
    }
}

extension FujiCamera {
    static let faceDetectionProperty: UInt16 = 0xD020
    static let eyeDetectionProperty: UInt16 = 0xD024

    func currentValue(of setting: CameraSetting) -> String? {
        guard setting == .faceDetection else { return readSettings([setting.rawValue])[setting.rawValue] }
        guard let face = readPropertyUInt16(Self.faceDetectionProperty), let eye = readPropertyUInt16(Self.eyeDetectionProperty) else { return nil }
        return FaceDetectionMode(face: face, eye: eye)?.rawValue
    }

    func availableValues(for setting: CameraSetting) -> [String] {
        guard setting == .faceDetection else { return choices(for: setting.rawValue) }
        return currentValue(of: .faceDetection) == nil ? [] : FaceDetectionMode.allCases.map(\.rawValue)
    }

    func apply(_ value: String, to setting: CameraSetting) -> Bool {
        if setting == .faceDetection, let mode = FaceDetectionMode(rawValue: value) {
            writePropertyUInt16(Self.faceDetectionProperty, mode.propertyValues.face)
            writePropertyUInt16(Self.eyeDetectionProperty, mode.propertyValues.eye)
        } else {
            try? writeSetting(setting.rawValue, value: value)
        }
        return currentValue(of: setting) == value
    }
}

enum CameraSettingsStore {
    private static let overridesKey = "cameraOverrides"
    private static let choicesKey = "cameraChoices"

    static func loadOverrides() -> [CameraSetting: String] {
        decode(UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: String] ?? [:])
    }

    static func save(overrides: [CameraSetting: String]) {
        UserDefaults.standard.set(encode(overrides), forKey: overridesKey)
    }

    static func loadChoices() -> [CameraSetting: [String]] {
        decode(UserDefaults.standard.dictionary(forKey: choicesKey) as? [String: [String]] ?? [:])
    }

    static func save(choices: [CameraSetting: [String]]) {
        UserDefaults.standard.set(encode(choices), forKey: choicesKey)
    }

    private static func decode<Value>(_ raw: [String: Value]) -> [CameraSetting: Value] {
        Dictionary(uniqueKeysWithValues: raw.compactMap { key, value in CameraSetting(rawValue: key).map { ($0, value) } })
    }

    private static func encode<Value>(_ values: [CameraSetting: Value]) -> [String: Value] {
        Dictionary(uniqueKeysWithValues: values.map { ($0.key.rawValue, $0.value) })
    }
}
