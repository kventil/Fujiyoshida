import Foundation

struct GPhotoError: LocalizedError {
    let code: Int32
    let operation: String

    var errorDescription: String? {
        let message = gp_result_as_string(code).map { String(cString: $0) } ?? "unknown error"
        return "\(operation) failed: \(message) (\(code))"
    }
}

final class FujiCamera {
    private let context: OpaquePointer?
    private var camera: UnsafeMutablePointer<Camera>?
    private(set) var modelName = ""

    var isConnected: Bool { camera != nil }

    init() {
        Self.useBundledDrivers()
        context = gp_context_new()
    }

    private static func useBundledDrivers() {
        guard let frameworks = Bundle.main.privateFrameworksURL?.appendingPathComponent("libgphoto2") else { return }
        let camlibs = frameworks.appendingPathComponent("camlibs")
        guard FileManager.default.fileExists(atPath: camlibs.path) else { return }
        setenv("CAMLIBS", camlibs.path, 1)
        setenv("IOLIBS", frameworks.appendingPathComponent("iolibs").path, 1)
    }

    deinit {
        disconnect()
        gp_context_unref(context)
    }

    func connect() throws {
        guard camera == nil else { return }
        Self.releaseCameraFromSystemDaemon()

        var newCamera: UnsafeMutablePointer<Camera>?
        try check(gp_camera_new(&newCamera), "gp_camera_new")
        let result = gp_camera_init(newCamera, context)
        guard result >= GP_OK else {
            gp_camera_unref(newCamera)
            throw GPhotoError(code: result, operation: "Connecting to camera")
        }
        camera = newCamera

        var abilities = CameraAbilities()
        if gp_camera_get_abilities(newCamera, &abilities) >= GP_OK {
            modelName = withUnsafeBytes(of: abilities.model) { raw in
                String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
            }
        }
    }

    func disconnect() {
        guard let camera else { return }
        gp_camera_exit(camera, context)
        gp_camera_unref(camera)
        self.camera = nil
        modelName = ""
    }

    func capturePreview() throws -> Data {
        guard let camera else { throw GPhotoError(code: GP_ERROR_CAMERA_ERROR, operation: "Preview") }
        var file: OpaquePointer?
        try check(gp_file_new(&file), "gp_file_new")
        defer { gp_file_unref(file) }

        try check(gp_camera_capture_preview(camera, file, context), "Capturing live view")

        var bytes: UnsafePointer<CChar>?
        var size: UInt = 0
        try check(gp_file_get_data_and_size(file, &bytes, &size), "Reading live view")
        guard let bytes, size > 0 else { throw GPhotoError(code: GP_ERROR_CORRUPTED_DATA, operation: "Reading live view") }
        return Data(bytes: bytes, count: Int(size))
    }

    func readSettings(_ names: [String]) -> [String: String] {
        guard let camera else { return [:] }
        var values: [String: String] = [:]
        for name in names {
            var widget: OpaquePointer?
            guard gp_camera_get_single_config(camera, name, &widget, context) >= GP_OK, let widget else { continue }
            defer { gp_widget_free(widget) }
            values[name] = Self.stringValue(of: widget)
        }
        return values
    }

    func writeSetting(_ name: String, value: String) throws {
        guard let camera else { throw GPhotoError(code: GP_ERROR_CAMERA_ERROR, operation: "Setting \(name)") }
        var widget: OpaquePointer?
        try check(gp_camera_get_single_config(camera, name, &widget, context), "Reading \(name)")
        guard let widget else { throw GPhotoError(code: GP_ERROR_CAMERA_ERROR, operation: "Reading \(name)") }
        defer { gp_widget_free(widget) }
        try value.withCString { try check(gp_widget_set_value(widget, $0), "Setting \(name)") }
        try check(gp_camera_set_single_config(camera, name, widget, context), "Setting \(name)")
    }

    func choices(for name: String) -> [String] {
        guard let camera else { return [] }
        var widget: OpaquePointer?
        guard gp_camera_get_single_config(camera, name, &widget, context) >= GP_OK, let widget else { return [] }
        defer { gp_widget_free(widget) }
        return (0..<max(gp_widget_count_choices(widget), 0)).compactMap { index in
            var choice: UnsafePointer<CChar>?
            guard gp_widget_get_choice(widget, index, &choice) >= GP_OK, let choice else { return nil }
            return String(cString: choice)
        }
    }

    func readPropertyString(_ code: UInt16) -> String? {
        readRawProperty(code).flatMap(Self.decodePTPString)
    }

    @discardableResult
    func writePropertyString(_ code: UInt16, _ value: String) -> Bool {
        var payload = Data([UInt8(value.utf16.count + 1)])
        for unit in value.utf16 { payload.append(UInt8(unit & 0xFF)); payload.append(UInt8(unit >> 8)) }
        payload.append(contentsOf: [0, 0])
        return writeProperty(code, payload)
    }

    func readPropertyUInt32(_ code: UInt16) -> UInt32? {
        guard let data = readRawProperty(code), !data.isEmpty else { return nil }
        return data.prefix(4).enumerated().reduce(0) { $0 | UInt32($1.element) << (8 * UInt32($1.offset)) }
    }

    func readPropertyUInt16(_ code: UInt16) -> UInt16? {
        guard let data = readRawProperty(code), data.count >= 2 else { return nil }
        return UInt16(data[data.startIndex]) | UInt16(data[data.startIndex + 1]) << 8
    }

    @discardableResult
    func writePropertyUInt16(_ code: UInt16, _ value: UInt16) -> Bool {
        writeProperty(code, Data([UInt8(value & 0xFF), UInt8(value >> 8)]))
    }

    func readFaceFrames() -> [String] {
        guard let data = readRawProperty(0xD18A), data.count >= 2 else { return [] }
        let count = Int(data[data.startIndex]) | Int(data[data.startIndex + 1]) << 8
        var frames: [String] = []
        var offset = data.startIndex + 2
        while frames.count < count, offset < data.endIndex {
            let length = Int(data[offset])
            let end = offset + 1 + length * 2
            guard length > 0, end <= data.endIndex, let text = Self.decodePTPString(data[offset..<end]) else { break }
            frames.append(text)
            offset = end
        }
        return frames
    }

    func stopLiveView() {
        guard let camera else { return }
        var request: OpaquePointer?
        guard gp_camera_get_single_config(camera, "opcode", &request, context) >= GP_OK, let request else { return }
        defer { gp_widget_free(request) }
        _ = gp_widget_set_value(request, "0x1018")
        _ = gp_camera_set_single_config(camera, "opcode", request, context)
    }

    func focusNow() throws {
        guard let camera else { throw GPhotoError(code: GP_ERROR_CAMERA_ERROR, operation: "Focusing") }
        var widget: OpaquePointer?
        try check(gp_camera_get_single_config(camera, "autofocusdrive", &widget, context), "Focusing")
        guard let widget else { throw GPhotoError(code: GP_ERROR_CAMERA_ERROR, operation: "Focusing") }
        defer { gp_widget_free(widget) }
        var on: Int32 = 1
        try check(gp_widget_set_value(widget, &on), "Focusing")
        try check(gp_camera_set_single_config(camera, "autofocusdrive", widget, context), "Focusing")
    }

    private func writeProperty(_ code: UInt16, _ payload: Data) -> Bool {
        guard let camera else { return false }
        let hex = payload.map { String(format: "%02x", $0) }.joined()
        var request: OpaquePointer?
        guard gp_camera_get_single_config(camera, "opcode", &request, context) >= GP_OK, let request else { return false }
        defer { gp_widget_free(request) }
        String(format: "0x1016,0x%04x;", code).appending(hex).withCString { _ = gp_widget_set_value(request, $0) }
        return gp_camera_set_single_config(camera, "opcode", request, context) >= GP_OK
    }

    private func readRawProperty(_ code: UInt16) -> Data? {
        guard let camera else { return nil }
        var request: OpaquePointer?
        guard gp_camera_get_single_config(camera, "opcode", &request, context) >= GP_OK, let request else { return nil }
        String(format: "0x1015,0x%04x", code).withCString { _ = gp_widget_set_value(request, $0) }
        let sent = gp_camera_set_single_config(camera, "opcode", request, context)
        gp_widget_free(request)
        guard sent >= GP_OK else { return nil }

        var response: OpaquePointer?
        guard gp_camera_get_single_config(camera, "opcode", &response, context) >= GP_OK, let response else { return nil }
        defer { gp_widget_free(response) }
        guard let text = Self.stringValue(of: response) else { return nil }

        let parts = text.split(separator: ":", maxSplits: 1)
        guard parts.first == "0x2001" else { return nil }
        guard parts.count == 2 else { return Data() }
        var data = Data(capacity: parts[1].count / 2)
        var index = parts[1].startIndex
        while let next = parts[1].index(index, offsetBy: 2, limitedBy: parts[1].endIndex), index < next {
            guard let byte = UInt8(parts[1][index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private static func decodePTPString(_ data: Data) -> String? {
        guard let count = data.first, count > 0, data.count >= 1 + Int(count) * 2 else { return nil }
        let units = (0..<Int(count) - 1).map { i -> UInt16 in
            UInt16(data[data.startIndex + 1 + i * 2]) | UInt16(data[data.startIndex + 2 + i * 2]) << 8
        }
        return String(decoding: units, as: UTF16.self)
    }

    private static func stringValue(of widget: OpaquePointer) -> String? {
        var type = GP_WIDGET_TEXT
        gp_widget_get_type(widget, &type)
        if type == GP_WIDGET_RANGE {
            var value: Float = 0
            gp_widget_get_value(widget, &value)
            return String(value)
        }
        if type == GP_WIDGET_TOGGLE || type == GP_WIDGET_DATE {
            var value: Int32 = 0
            gp_widget_get_value(widget, &value)
            return String(value)
        }
        var value: UnsafeMutablePointer<CChar>?
        gp_widget_get_value(widget, &value)
        return value.map { String(cString: $0) }
    }

    private func check(_ result: Int32, _ operation: String) throws {
        if result < GP_OK { throw GPhotoError(code: result, operation: operation) }
    }

    private static func releaseCameraFromSystemDaemon() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-9", "ptpcamerad"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
