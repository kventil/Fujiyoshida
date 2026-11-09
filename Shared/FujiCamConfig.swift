import CoreMedia
import CoreVideo

enum FujiCamConfig {
    static let extensionBundleID = "com.robertbahmann.FujiCam.CameraExtension"
    static let deviceUID = "8B1F6C2E-4A7D-4E3B-9C51-F0C1A2D3E4B5"
    static let sourceStreamUID = "8B1F6C2E-4A7D-4E3B-9C51-F0C1A2D3E4B6"
    static let sinkStreamUID = "8B1F6C2E-4A7D-4E3B-9C51-F0C1A2D3E4B7"
    static let deviceName = "FujiCam X-T4"
    static let width: Int32 = 1280
    static let height: Int32 = 720
    static let frameRate: Int32 = 30
    static let pixelFormat: OSType = kCVPixelFormatType_32BGRA
}
