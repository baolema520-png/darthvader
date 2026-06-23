import CoreGraphics
import Foundation

enum AvatarRegion: String, CaseIterable, Sendable {
    case mouth
    case leftEye
    case rightEye
    case leftBrow
    case rightBrow
    case nose
    case jawline
}

struct AvatarVertex: Sendable, Equatable {
    var position: CGPoint
    var uv: CGPoint
}

struct AvatarMesh: Sendable, Equatable {
    var vertices: [AvatarVertex]
    var indices: [UInt16]
}

struct AvatarModel: Sendable, Equatable {
    var texturePath: URL
    var mesh: AvatarMesh
    var referenceLandmarks: [CGPoint]
    var vertexLandmarkMap: [Int]
    var segmentedRegionVertexIndices: [AvatarRegion: [Int]]
    var regionLandmarkIndices: [AvatarRegion: [Int]]
    var featureAnchors: AvatarFeatureAnchors
    var identityMetadata: [String: Float]
}

struct AvatarFeatureAnchors: Sendable, Equatable {
    var leftEyeCenter: CGPoint
    var rightEyeCenter: CGPoint
    var mouthCenter: CGPoint
    var mouthSize: CGSize

    static let neutral = AvatarFeatureAnchors(
        leftEyeCenter: CGPoint(x: 0.35, y: 0.62),
        rightEyeCenter: CGPoint(x: 0.65, y: 0.62),
        mouthCenter: CGPoint(x: 0.5, y: 0.34),
        mouthSize: CGSize(width: 0.18, height: 0.10)
    )
}
