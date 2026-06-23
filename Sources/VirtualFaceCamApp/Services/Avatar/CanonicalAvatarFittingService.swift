import CoreGraphics
import Foundation

struct CanonicalAvatarFitResult: Sendable {
    let identityMetadata: [String: Float]
    let source: String
}

final class CanonicalAvatarFittingService {
    func runBuiltInFitting(preprocess: AvatarPreprocessResult) -> CanonicalAvatarFitResult {
        let mouth = preprocess.regionPoints[.mouth] ?? []
        let leftEye = preprocess.regionPoints[.leftEye] ?? []
        let rightEye = preprocess.regionPoints[.rightEye] ?? []
        let leftBrow = preprocess.regionPoints[.leftBrow] ?? []
        let rightBrow = preprocess.regionPoints[.rightBrow] ?? []

        let mouthWidth = width(of: mouth, fallback: 0.24)
        let mouthHeight = height(of: mouth, fallback: 0.10)
        let eyeWidth = (width(of: leftEye, fallback: 0.10) + width(of: rightEye, fallback: 0.10)) * 0.5
        let eyeHeight = (height(of: leftEye, fallback: 0.06) + height(of: rightEye, fallback: 0.06)) * 0.5
        let browHeight = (height(of: leftBrow, fallback: 0.06) + height(of: rightBrow, fallback: 0.06)) * 0.5
        let eyeCenterDistance = distance(center(of: leftEye), center(of: rightEye), fallback: 0.28)
        let faceAspect = max(0.65, min(1.60, Float(preprocess.faceBoundingBox.height / max(0.0001, preprocess.faceBoundingBox.width))))
        let mouthCenterY = center(of: mouth)?.y ?? 0.35

        // Fully local canonical fitting profile (no scripts, no external runtimes).
        let identity: [String: Float] = [
            "mouthScale": clamp(mouthWidth / 0.24, min: 0.80, max: 1.25),
            "eyeScale": clamp(eyeWidth / 0.10, min: 0.82, max: 1.20),
            "browScale": clamp(browHeight / 0.06, min: 0.80, max: 1.22),
            "headScaleY": clamp(faceAspect / 1.20, min: 0.84, max: 1.28),
            "eyeSpacingScale": clamp(eyeCenterDistance / 0.28, min: 0.85, max: 1.20),
            "mouthHeightScale": clamp(mouthHeight / 0.10, min: 0.72, max: 1.42),
            "eyeHeightScale": clamp(eyeHeight / 0.06, min: 0.75, max: 1.34),
            "jawDepthScale": clamp(mouthHeight / 0.10, min: 0.75, max: 1.35),
            "mouthVerticalOffset": clamp((0.36 - Float(mouthCenterY)) * 0.6, min: -0.08, max: 0.08)
        ]
        return CanonicalAvatarFitResult(identityMetadata: identity, source: "built-in-local")
    }

    private func width(of points: [CGPoint], fallback: Float) -> Float {
        guard !points.isEmpty else { return fallback }
        let xs = points.map(\.x)
        guard let minX = xs.min(), let maxX = xs.max() else { return fallback }
        return Float(maxX - minX)
    }

    private func height(of points: [CGPoint], fallback: Float) -> Float {
        guard !points.isEmpty else { return fallback }
        let ys = points.map(\.y)
        guard let minY = ys.min(), let maxY = ys.max() else { return fallback }
        return Float(maxY - minY)
    }

    private func clamp(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    private func center(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let x = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let y = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        return CGPoint(x: x, y: y)
    }

    private func distance(_ a: CGPoint?, _ b: CGPoint?, fallback: Float) -> Float {
        guard let a, let b else { return fallback }
        let dx = a.x - b.x
        let dy = a.y - b.y
        return Float(sqrt(dx * dx + dy * dy))
    }
}
