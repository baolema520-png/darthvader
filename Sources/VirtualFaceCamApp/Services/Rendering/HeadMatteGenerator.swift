import CoreImage
import CoreVideo
import Foundation
import Vision

final class HeadMatteGenerator {
    private let request = VNGeneratePersonSegmentationRequest()
    private let requestHandler = VNSequenceRequestHandler()
    private var cachedMask: CIImage?
    private var cachedFullBodyMask: CIImage?
    private var frameIndex: Int = 0

    init() {
        request.qualityLevel = .balanced
        request.outputPixelFormat = kCVPixelFormatType_OneComponent8
    }

    func maskImage(
        sourceFrame: CVPixelBuffer,
        faceBoundingBox: CGRect,
        extent: CGRect
    ) -> CIImage? {
        guard let fullMask = fullBodyMaskImage(sourceFrame: sourceFrame, extent: extent) else {
            return cachedMask
        }
        let headRect = CGRect(
            x: faceBoundingBox.minX * extent.width - faceBoundingBox.width * extent.width * 0.36,
            y: faceBoundingBox.minY * extent.height - faceBoundingBox.height * extent.height * 0.65,
            width: faceBoundingBox.width * extent.width * 1.72,
            height: faceBoundingBox.height * extent.height * 2.52
        ).intersection(extent)
        let whiteRect = CIImage(color: .white).cropped(to: headRect)
        let headWindow = whiteRect
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 14])
            .cropped(to: extent)
        cachedMask = fullMask.applyingFilter(
            "CIMultiplyCompositing",
            parameters: [kCIInputBackgroundImageKey: headWindow]
        )
        return cachedMask
    }

    func fullBodyMaskImage(sourceFrame: CVPixelBuffer, extent: CGRect) -> CIImage? {
        frameIndex += 1
        let shouldRefresh = frameIndex.isMultiple(of: 2) || cachedFullBodyMask == nil
        if shouldRefresh {
            do {
                try requestHandler.perform([request], on: sourceFrame)
                if let pixelBuffer = request.results?.first?.pixelBuffer {
                    let rawMask = CIImage(cvPixelBuffer: pixelBuffer)
                    let scaleX = extent.width / max(rawMask.extent.width, 1)
                    let scaleY = extent.height / max(rawMask.extent.height, 1)
                    let scaled = rawMask
                        .transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
                        .cropped(to: extent)
                    cachedFullBodyMask = scaled
                        .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 6])
                        .cropped(to: extent)
                        .applyingFilter("CIColorControls", parameters: [
                            kCIInputBrightnessKey: 0.02,
                            kCIInputContrastKey: 1.25
                        ])
                        .cropped(to: extent)
                }
            } catch {
                // Best effort: conservar ultima mascara valida.
            }
        }
        return cachedFullBodyMask
    }
}
