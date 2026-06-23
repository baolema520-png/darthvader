import CoreGraphics
import Foundation

struct InternalIdentityRegressor {
    func embedding(from landmarks: FaceLandmarks) -> [Float] {
        let faceBounds = boundingBox(of: landmarks.faceContourPoints)
        let mouthBounds = boundingBox(of: landmarks.mouthOuterPoints)
        let noseBounds = boundingBox(of: landmarks.nosePoints)
        let leftEyeBounds = boundingBox(of: landmarks.leftEyePoints)
        let rightEyeBounds = boundingBox(of: landmarks.rightEyePoints)

        let eyeDistance = distance(centroid(of: landmarks.leftEyePoints), centroid(of: landmarks.rightEyePoints))
        let faceWidth = max(faceBounds.width, 0.0001)
        let faceHeight = max(faceBounds.height, 0.0001)

        let raw: [Float] = [
            Float(faceWidth / faceHeight),
            Float(eyeDistance / faceWidth),
            Float(mouthBounds.width / faceWidth),
            Float(mouthBounds.height / faceHeight),
            Float(noseBounds.width / faceWidth),
            Float(leftEyeBounds.width / faceWidth),
            Float(rightEyeBounds.width / faceWidth),
            Float((leftEyeBounds.height + rightEyeBounds.height) * 0.5 / faceHeight),
            landmarks.jawOpen,
            landmarks.mouthOpen,
            landmarks.mouthWidth,
            landmarks.lipPucker,
            landmarks.leftEyeBlink,
            landmarks.rightEyeBlink,
            landmarks.headEulerAngles.x,
            landmarks.headEulerAngles.y
        ]

        let norm = sqrt(raw.reduce(0) { $0 + $1 * $1 })
        guard norm > 0.0001 else { return raw }
        return raw.map { $0 / norm }
    }

    func metadata(from embedding: [Float]) -> [String: Float] {
        guard embedding.count >= 8 else { return [:] }
        return [
            "replicaFaceAspect": embedding[0],
            "replicaEyeSpacing": embedding[1],
            "replicaMouthWidth": embedding[2],
            "replicaMouthHeight": embedding[3],
            "replicaNoseWidth": embedding[4],
            "replicaEyeWidthLeft": embedding[5],
            "replicaEyeWidthRight": embedding[6],
            "replicaEyeHeight": embedding[7]
        ]
    }
}

private extension InternalIdentityRegressor {
    func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return .zero }
        let x = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let y = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        return CGPoint(x: x, y: y)
    }

    func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
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
}
