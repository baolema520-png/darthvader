import CoreGraphics
import Foundation

struct CanonicalBlendshapeRig: Sendable, Equatable {
    struct Influence: Sendable, Equatable {
        var vertexIndices: [Int]
        var delta: CGPoint
    }

    var influences: [String: [Influence]]

    static let empty = CanonicalBlendshapeRig(influences: [:])

    func apply(to mesh: inout AvatarMesh, coefficients: [String: Float], confidence: Float) {
        guard !influences.isEmpty else { return }
        let confidenceScale = CGFloat(max(0.2, confidence))
        for (shapeName, weight) in coefficients {
            guard let shapeInfluences = influences[shapeName], weight > 0.001 else { continue }
            let w = CGFloat(weight) * confidenceScale
            for influence in shapeInfluences {
                for idx in influence.vertexIndices where mesh.vertices.indices.contains(idx) {
                    var p = mesh.vertices[idx].position
                    p.x = clamp01(p.x + influence.delta.x * w)
                    p.y = clamp01(p.y + influence.delta.y * w)
                    mesh.vertices[idx].position = p
                }
            }
        }
    }

    private func clamp01(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}
