import AVFoundation
import CoreGraphics
import Foundation
import Vision

final class FaceTrackingService: FaceTrackingProviding {
    var onLandmarks: ((FaceLandmarks?) -> Void)?

    private let queue = DispatchQueue(label: "FaceTrackingService.Queue", qos: .userInitiated)
    private let sequenceRequestHandler = VNSequenceRequestHandler()
    private let temporalFilter = FaceTemporalFilter(alpha: 0.80)
    private let professionalPipeline: ProfessionalFacePipeline?
    private let visionExtractor = VisionFaceLandmarkExtractor()
    private var isProcessingFrame = false

    init(professionalPipeline: ProfessionalFacePipeline? = nil) {
        self.professionalPipeline = professionalPipeline
    }

    func process(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            onLandmarks?(nil)
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isProcessingFrame else { return }
            self.isProcessingFrame = true
            defer { self.isProcessingFrame = false }

            if let professionalLandmarks = self.professionalPipeline?.process(sampleBuffer: sampleBuffer) {
                self.onLandmarks?(self.temporalFilter.filter(professionalLandmarks))
                return
            }

            do {
                guard let mapped = try self.visionExtractor.extract(
                    from: pixelBuffer,
                    sequenceRequestHandler: self.sequenceRequestHandler
                ) else {
                    self.onLandmarks?(nil)
                    self.temporalFilter.reset()
                    return
                }
                self.onLandmarks?(self.temporalFilter.filter(mapped))
            } catch {
                self.onLandmarks?(nil)
                self.temporalFilter.reset()
            }
        }
    }
}
