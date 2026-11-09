import Foundation
import SystemExtensions

final class ExtensionInstaller: NSObject, ObservableObject, OSSystemExtensionRequestDelegate {
    @Published private(set) var status = "Camera extension: unknown"

    func activate() {
        submit(.activationRequest(forExtensionWithIdentifier: FujiCamConfig.extensionBundleID, queue: .main))
        status = "Camera extension: installing…"
    }

    func deactivate() {
        submit(.deactivationRequest(forExtensionWithIdentifier: FujiCamConfig.extensionBundleID, queue: .main))
        status = "Camera extension: removing…"
    }

    private func submit(_ request: OSSystemExtensionRequest) {
        request.delegate = self
        OSSystemExtensionManager.shared.submitRequest(request)
    }

    func request(_ request: OSSystemExtensionRequest,
                 actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        status = "Approve in System Settings › General › Login Items & Extensions"
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        switch result {
        case .completed: status = "Camera extension: ready"
        case .willCompleteAfterReboot: status = "Camera extension: restart required"
        @unknown default: status = "Camera extension: \(result.rawValue)"
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        status = "Camera extension error: \(error.localizedDescription)"
    }
}
