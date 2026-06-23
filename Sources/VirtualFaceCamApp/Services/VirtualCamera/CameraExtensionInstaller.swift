import Foundation
import OSLog
import SystemExtensions

final class CameraExtensionInstaller: NSObject {
    static let extensionIdentifier = "com.virtualfacecam.app.cameraextension"
    private let logger = Logger(subsystem: "com.virtualfacecam.app", category: "CameraExtensionInstaller")

    enum ActivationState {
        case submitting
        case needsUserApproval
        case completed
        case failed(String)
    }

    private var completion: ((Result<Void, Error>) -> Void)?
    private var stateHandler: ((ActivationState) -> Void)?
    private var currentRequest: OSSystemExtensionRequest?
    private var lastActivationContext: String = ""

    enum InstallerError: LocalizedError {
        case appMustRunFromApplications
        case embeddedExtensionNotFound(String)

        var errorDescription: String? {
            switch self {
            case .appMustRunFromApplications:
                return "La app debe ejecutarse desde /Applications para activar la extension de camara."
            case .embeddedExtensionNotFound(let details):
                return "No se encontro una system extension valida en el bundle. \(details)"
            }
        }
    }

    func activateIfNeeded(
        stateHandler: @escaping (ActivationState) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let bundlePath = Bundle.main.bundleURL.path
        logger.info("Activation requested. bundlePath=\(bundlePath, privacy: .public)")
        if !bundlePath.hasPrefix("/Applications/") {
            let error = InstallerError.appMustRunFromApplications
            logger.error("Activation blocked: app is not in /Applications")
            stateHandler(.failed(error.localizedDescription))
            completion(.failure(error))
            return
        }

        let discoveredIDs = discoverEmbeddedSystemExtensionIdentifiers()
        logger.info("Discovered system extension IDs: \(discoveredIDs.joined(separator: ","), privacy: .public)")
        guard !discoveredIDs.isEmpty else {
            let details = "Bundle: \(bundlePath). Ruta esperada: \(Bundle.main.bundleURL.path)/Contents/Library/SystemExtensions"
            let error = InstallerError.embeddedExtensionNotFound(details)
            logger.error("Activation blocked: no embedded system extension found")
            stateHandler(.failed(error.localizedDescription))
            completion(.failure(error))
            return
        }

        let identifierToActivate: String
        if discoveredIDs.contains(Self.extensionIdentifier) {
            identifierToActivate = Self.extensionIdentifier
        } else {
            // Fallback robusto: usar el identificador realmente embebido.
            identifierToActivate = discoveredIDs[0]
        }
        lastActivationContext = "bundlePath=\(bundlePath) | discoveredIDs=\(discoveredIDs.joined(separator: ",")) | selectedID=\(identifierToActivate)"
        logger.info("Submitting activation request for ID \(identifierToActivate, privacy: .public)")

        self.stateHandler = stateHandler
        self.completion = completion
        stateHandler(.submitting)
        let request = OSSystemExtensionRequest.activationRequest(
            forExtensionWithIdentifier: identifierToActivate,
            queue: .main
        )
        request.delegate = self
        currentRequest = request
        OSSystemExtensionManager.shared.submitRequest(request)
    }
}

private extension CameraExtensionInstaller {
    func discoverEmbeddedSystemExtensionIdentifiers() -> [String] {
        let systemExtensionsURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Library")
            .appendingPathComponent("SystemExtensions")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: systemExtensionsURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var ids: [String] = []
        for entry in entries where entry.pathExtension == "systemextension" {
            let infoURL = entry
                .appendingPathComponent("Contents")
                .appendingPathComponent("Info.plist")
            guard
                let data = try? Data(contentsOf: infoURL),
                let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
                let dict = plist as? [String: Any],
                let bundleID = dict["CFBundleIdentifier"] as? String
            else { continue }
            ids.append(bundleID)
        }
        return ids
    }
}

extension CameraExtensionInstaller: OSSystemExtensionRequestDelegate {
    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        _ = request
        _ = result
        logger.info("Activation finished successfully")
        stateHandler?(.completed)
        completion?(.success(()))
        currentRequest = nil
        stateHandler = nil
        completion = nil
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        _ = request
        let nsError = error as NSError
        let reason = (nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String) ?? "sin detalle"
        let detail = "\(nsError.domain) (\(nsError.code)): \(nsError.localizedDescription). Motivo: \(reason). Contexto: \(lastActivationContext). userInfo=\(nsError.userInfo)"
        logger.error("Activation failed: \(detail, privacy: .public)")
        stateHandler?(.failed(detail))
        completion?(.failure(error))
        currentRequest = nil
        lastActivationContext = ""
        stateHandler = nil
        completion = nil
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        _ = request
        logger.info("Activation requires user approval in System Settings")
        stateHandler?(.needsUserApproval)
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        _ = request
        _ = existing
        _ = ext
        return .replace
    }
}
