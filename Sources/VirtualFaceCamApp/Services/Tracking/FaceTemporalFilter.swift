import CoreGraphics
import Foundation
import simd

final class FaceTemporalFilter {
    private var previous: FaceLandmarks?
    private var alpha: Float

    init(alpha: Float = 0.35) {
        self.alpha = min(max(alpha, 0.05), 0.95)
    }

    func updateAlpha(_ alpha: Float) {
        self.alpha = min(max(alpha, 0.05), 0.95)
    }

    func reset() {
        previous = nil
    }

    func filter(_ current: FaceLandmarks) -> FaceLandmarks {
        guard let previous else {
            self.previous = current
            return current
        }

        let mouthVelocity = abs(current.mouthOpen - previous.mouthOpen) + abs(current.jawOpen - previous.jawOpen)
        let eyeVelocity = abs(current.leftEyeBlink - previous.leftEyeBlink) + abs(current.rightEyeBlink - previous.rightEyeBlink)
        // Adaptive response: fast channels react quicker when movement is strong,
        // while keeping slow channels stable to reduce flicker.
        let fastBoost = min(0.22, mouthVelocity * 1.8 + eyeVelocity * 1.4)
        let fastAlpha = min(0.94, alpha + 0.2 + fastBoost)
        let stableAlpha = alpha
        let slowAlpha = max(0.18, alpha - 0.22)

        let smoothed = FaceLandmarks(
            boundingBox: lerp(previous.boundingBox, current.boundingBox, t: stableAlpha),
            mouthOpen: lerp(previous.mouthOpen, current.mouthOpen, t: fastAlpha),
            jawOpen: lerp(previous.jawOpen, current.jawOpen, t: fastAlpha),
            mouthWidth: lerp(previous.mouthWidth, current.mouthWidth, t: stableAlpha),
            lipPucker: lerp(previous.lipPucker, current.lipPucker, t: fastAlpha),
            leftEyeBlink: lerp(previous.leftEyeBlink, current.leftEyeBlink, t: fastAlpha),
            rightEyeBlink: lerp(previous.rightEyeBlink, current.rightEyeBlink, t: fastAlpha),
            leftEyeOpen: lerp(previous.leftEyeOpen, current.leftEyeOpen, t: fastAlpha),
            rightEyeOpen: lerp(previous.rightEyeOpen, current.rightEyeOpen, t: fastAlpha),
            leftBrowRaise: lerp(previous.leftBrowRaise, current.leftBrowRaise, t: stableAlpha),
            rightBrowRaise: lerp(previous.rightBrowRaise, current.rightBrowRaise, t: stableAlpha),
            gazeX: lerp(previous.gazeX, current.gazeX, t: fastAlpha),
            gazeY: lerp(previous.gazeY, current.gazeY, t: fastAlpha),
            headEulerAngles: simd_mix(previous.headEulerAngles, current.headEulerAngles, simd_float3(repeating: slowAlpha)),
            normalizedPoints: blendPoints(previous.normalizedPoints, current.normalizedPoints, alpha: stableAlpha),
            faceContourPoints: blendPoints(previous.faceContourPoints, current.faceContourPoints, alpha: stableAlpha),
            mouthOuterPoints: blendPoints(previous.mouthOuterPoints, current.mouthOuterPoints, alpha: fastAlpha),
            leftEyePoints: blendPoints(previous.leftEyePoints, current.leftEyePoints, alpha: fastAlpha),
            rightEyePoints: blendPoints(previous.rightEyePoints, current.rightEyePoints, alpha: fastAlpha),
            leftBrowPoints: blendPoints(previous.leftBrowPoints, current.leftBrowPoints, alpha: stableAlpha),
            rightBrowPoints: blendPoints(previous.rightBrowPoints, current.rightBrowPoints, alpha: stableAlpha),
            nosePoints: blendPoints(previous.nosePoints, current.nosePoints, alpha: stableAlpha),
            expressionConfidence: lerp(previous.expressionConfidence, current.expressionConfidence, t: stableAlpha),
            blendshapeCoefficients: blendBlendshapes(previous: previous.blendshapeCoefficients, current: current.blendshapeCoefficients, alpha: fastAlpha)
        )

        self.previous = smoothed
        return smoothed
    }
}

private extension FaceTemporalFilter {
    func lerp(_ a: Float, _ b: Float, t: Float) -> Float {
        a + (b - a) * t
    }

    func lerp(_ a: CGRect, _ b: CGRect, t: Float) -> CGRect {
        CGRect(
            x: CGFloat(Float(a.origin.x) + (Float(b.origin.x) - Float(a.origin.x)) * t),
            y: CGFloat(Float(a.origin.y) + (Float(b.origin.y) - Float(a.origin.y)) * t),
            width: CGFloat(Float(a.width) + (Float(b.width) - Float(a.width)) * t),
            height: CGFloat(Float(a.height) + (Float(b.height) - Float(a.height)) * t)
        )
    }

    func blendPoints(_ previous: [CGPoint], _ current: [CGPoint], alpha: Float) -> [CGPoint] {
        guard !previous.isEmpty, !current.isEmpty else { return current }
        guard previous.count == current.count else { return current }
        return zip(previous, current).map { old, new in
            CGPoint(
                x: old.x + (new.x - old.x) * CGFloat(alpha),
                y: old.y + (new.y - old.y) * CGFloat(alpha)
            )
        }
    }

    func blendBlendshapes(previous: [String: Float], current: [String: Float], alpha: Float) -> [String: Float] {
        guard !current.isEmpty else { return previous }
        var output = current
        for (name, currentValue) in current {
            let oldValue = previous[name] ?? currentValue
            output[name] = oldValue + (currentValue - oldValue) * alpha
        }
        return output
    }
}
