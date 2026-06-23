import AVFoundation
import Foundation
import Vision

#if canImport(OnnxRuntimeBindings)
import OnnxRuntimeBindings
#endif

final class ProfessionalFacePipeline {
    static let shared = ProfessionalFacePipeline()

    private let assetManager: ProfessionalModelAssetManager
    private let visionExtractor = VisionFaceLandmarkExtractor()
    private let denseReplica = InternalDenseFittingReplica()
    private let identityReplica = InternalIdentityRegressor()
    private let sequenceRequestHandler = VNSequenceRequestHandler()
    private let stateQueue = DispatchQueue(label: "ProfessionalFacePipeline.StateQueue", qos: .userInitiated)
    private var latestIdentityEmbedding: [Float] = []
    private var latestIdentityMetadata: [String: Float] = [:]

    init(assetManager: ProfessionalModelAssetManager = .shared) {
        self.assetManager = assetManager
        try? assetManager.ensureModelDirectory()
    }

    var status: ProfessionalPipelineStatus {
        ProfessionalPipelineStatus(
            isOnnxRuntimeAvailable: Self.isOnnxRuntimeAvailable,
            availableModels: assetManager.existingModels(),
            missingModels: assetManager.missingModels(),
            usingInternalReplica: true,
            replicaComponents: ["dense_fitting_replica", "identity_regressor_replica"]
        )
    }

    static var isOnnxRuntimeAvailable: Bool {
        #if canImport(OnnxRuntimeBindings)
        return true
        #else
        return false
        #endif
    }

    func trackingBackendDescription() -> String {
        let currentStatus = status
        if currentStatus.isReady {
            if !currentStatus.availableModels.isEmpty {
                return "Pipeline local autocontenido (recursos bundleados + replicas internas)"
            }
            return "Pipeline local autocontenido (replicas internas)"
        }
        return "Pipeline local pendiente"
    }

    func process(sampleBuffer: CMSampleBuffer) -> FaceLandmarks? {
        processAll(sampleBuffer: sampleBuffer, maxFaces: 1).first
    }

    func processAll(sampleBuffer: CMSampleBuffer, maxFaces: Int) -> [FaceLandmarks] {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return [] }
        guard let extracted = try? visionExtractor.extractUpTo(
            maxFaces: maxFaces,
            from: pixelBuffer,
            sequenceRequestHandler: sequenceRequestHandler
        ), !extracted.isEmpty else {
            return []
        }

        return extracted.map { face in
            let fitted = denseReplica.refine(face)
            let embedding = identityReplica.embedding(from: fitted)
            let metadata = identityReplica.metadata(from: embedding)
            stateQueue.sync {
                latestIdentityEmbedding = embedding
                latestIdentityMetadata = metadata
            }
            return fitted
        }
    }

    private func processLegacy(sampleBuffer: CMSampleBuffer) -> FaceLandmarks? {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return nil }
        guard let extracted = try? visionExtractor.extract(
            from: pixelBuffer,
            sequenceRequestHandler: sequenceRequestHandler
        ) else {
            return nil
        }

        let fitted = denseReplica.refine(extracted)
        let embedding = identityReplica.embedding(from: fitted)
        let metadata = identityReplica.metadata(from: embedding)
        stateQueue.sync {
            latestIdentityEmbedding = embedding
            latestIdentityMetadata = metadata
        }
        return fitted
    }
}
