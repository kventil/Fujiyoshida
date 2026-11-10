import CoreMedia
import CoreVideo

enum FujiyoshidaConfig {
    static let extensionBundleID = "com.robertbahmann.Fujiyoshida.CameraExtension"
    static let deviceUID = "3E9A7C41-6B2D-4F18-A5C3-7D0E9B1F2A61"
    static let sourceStreamUID = "3E9A7C41-6B2D-4F18-A5C3-7D0E9B1F2A62"
    static let sinkStreamUID = "3E9A7C41-6B2D-4F18-A5C3-7D0E9B1F2A63"
    static let deviceName = "Fujiyoshida X-T4"
    static let width: Int32 = 1280
    static let height: Int32 = 720
    static let frameRate: Int32 = 30
    static let pixelFormat: OSType = kCVPixelFormatType_32BGRA
    static let viewerPropertyName = "4cc_fjyv_glob_0000"
    static let viewerPropertySelector: UInt32 = 0x666A_7976
}
