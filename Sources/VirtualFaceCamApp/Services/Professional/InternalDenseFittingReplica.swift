import CoreGraphics
import Foundation
import simd

struct InternalDenseFittingReplica {
    func refine(_ landmarks: FaceLandmarks) -> FaceLandmarks {
        var refined = landmarks
        let densified = densifyLandmarks(landmarks)
        if !densified.isEmpty {
            refined.normalizedPoints = densified
        }

        let contourBox = boundingBox(of: landmarks.faceContourPoints)
        let contourAspect = Float(contourBox.height / max(contourBox.width, 0.0001))
        let eyeRollCompensation = (landmarks.leftEyeBlink - landmarks.rightEyeBlink) * 0.04
        refined.headEulerAngles = simd_float3(
            landmarks.headEulerAngles.x * 1.08,
            landmarks.headEulerAngles.y * 1.15,
            landmarks.headEulerAngles.z + eyeRollCompensation
        )
        refined.expressionConfidence = min(1, max(landmarks.expressionConfidence, 0.82))

        var enriched = landmarks.blendshapeCoefficients
        enriched["cheekSquintLeft"] = clamp01(landmarks.leftEyeBlink * 0.55 + landmarks.mouthWidth * 0.10)
        enriched["cheekSquintRight"] = clamp01(landmarks.rightEyeBlink * 0.55 + landmarks.mouthWidth * 0.10)
        enriched["noseSneerLeft"] = clamp01(max(0, contourAspect - 1.0) * 0.2 + landmarks.lipPucker * 0.18)
        enriched["noseSneerRight"] = enriched["noseSneerLeft"]
        enriched["jawForward"] = clamp01(landmarks.jawOpen * 0.35 + max(0, landmarks.headEulerAngles.y) * 0.2)
        refined.blendshapeCoefficients = enriched
        return refined
    }
}

private extension InternalDenseFittingReplica {
    func densifyLandmarks(_ landmarks: FaceLandmarks) -> [CGPoint] {
        let regions = [
            landmarks.faceContourPoints,
            landmarks.leftEyePoints,
            landmarks.rightEyePoints,
            landmarks.leftBrowPoints,
            landmarks.rightBrowPoints,
            landmarks.nosePoints,
            landmarks.mouthOuterPoints
        ]
        return regions.flatMap { densify(points: $0) }
    }

    func densify(points: [CGPoint]) -> [CGPoint] {
        guard points.count >= 2 else { return points }
        var result: [CGPoint] = []
        result.reserveCapacity(points.count * 2)
        for index in points.indices {
            let current = points[index]
            result.append(current)
            let next = points[(index + 1) % points.count]
            let midpoint = CGPoint(x: (current.x + next.x) * 0.5, y: (current.y + next.y) * 0.5)
            result.append(midpoint)
        }
        return result
    }

    func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for point in points {
            minX = min(minX, point.x)
            minY = min(minY, point.y)
            maxX = max(maxX, point.x)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: max(0.0001, maxX - minX), height: max(0.0001, maxY - minY))
    }

    func clamp01(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
