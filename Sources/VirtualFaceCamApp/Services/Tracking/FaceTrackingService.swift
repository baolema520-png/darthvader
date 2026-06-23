import AVFoundation
import CoreGraphics
import Foundation
import Vision

final class FaceTrackingService: FaceTrackingProviding {
    var onLandmarks: (([FaceLandmarks]) -> Void)?

    private let queue = DispatchQueue(label: "FaceTrackingService.Queue", qos: .userInitiated)
    private let sequenceRequestHandler = VNSequenceRequestHandler()
    private let temporalFilter = MultiFaceTemporalFilter(alpha: 0.80)
    private let professionalPipeline: ProfessionalFacePipeline?
    private let visionExtractor = VisionFaceLandmarkExtractor()
    private var isProcessingFrame = false

    init(professionalPipeline: ProfessionalFacePipeline? = nil) {
        self.professionalPipeline = professionalPipeline
    }

    func process(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            onLandmarks?([])
            return
        }

        queue.async { [weak self] in
            guard let self else { return }
            guard !self.isProcessingFrame else { return }
            self.isProcessingFrame = true
            defer { self.isProcessingFrame = false }

            if let professionalFaces = self.professionalPipeline?.processAll(
                sampleBuffer: sampleBuffer,
                maxFaces: MultiFaceTemporalFilter.maxTrackedFaces
            ), !professionalFaces.isEmpty {
                self.onLandmarks?(self.temporalFilter.filter(professionalFaces))
                return
            }

            do {
                let detected = try self.visionExtractor.extractUpTo(
                    maxFaces: MultiFaceTemporalFilter.maxTrackedFaces,
                    from: pixelBuffer,
                    sequenceRequestHandler: self.sequenceRequestHandler
                )
                guard !detected.isEmpty else {
                    self.onLandmarks?([])
                    self.temporalFilter.reset()
                    return
                }
                self.onLandmarks?(self.temporalFilter.filter(detected))
            } catch {
                self.onLandmarks?([])
                self.temporalFilter.reset()
            }
        }
    }
}
