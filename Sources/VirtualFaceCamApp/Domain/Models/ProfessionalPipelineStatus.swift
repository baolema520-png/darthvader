import Foundation

struct ProfessionalPipelineStatus: Sendable, Equatable {
    var isOnnxRuntimeAvailable: Bool
    var availableModels: [String]
    var missingModels: [String]
    var usingInternalReplica: Bool
    var replicaComponents: [String]

    var isReady: Bool {
        usingInternalReplica || (isOnnxRuntimeAvailable && missingModels.isEmpty)
    }

    var summary: String {
        if isReady {
            if usingInternalReplica {
                return "Pipeline pro autocontenido (\(availableModels.count) recursos bundleados + \(replicaComponents.count) replicas internas)"
            }
            return "Pipeline pro local listo (\(availableModels.count) recursos bundleados)"
        }
        if !isOnnxRuntimeAvailable {
            return "Pipeline pro no disponible"
        }
        if !missingModels.isEmpty {
            return "Pipeline pro incompleto: faltan \(missingModels.count) recursos bundleados"
        }
        return "Pipeline pro pendiente"
    }
}
