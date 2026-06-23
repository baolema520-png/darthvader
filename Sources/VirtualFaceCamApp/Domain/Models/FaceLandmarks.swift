import CoreGraphics
import simd

struct FaceLandmarks: Sendable, Equatable {
    var boundingBox: CGRect
    var mouthOpen: Float
    var jawOpen: Float
    var mouthWidth: Float
    var lipPucker: Float
    var leftEyeBlink: Float
    var rightEyeBlink: Float
    var leftEyeOpen: Float
    var rightEyeOpen: Float
    var leftBrowRaise: Float
    var rightBrowRaise: Float
    var gazeX: Float
    var gazeY: Float
    var headEulerAngles: simd_float3
    var normalizedPoints: [CGPoint]
    var faceContourPoints: [CGPoint]
    var mouthOuterPoints: [CGPoint]
    var leftEyePoints: [CGPoint]
    var rightEyePoints: [CGPoint]
    var leftBrowPoints: [CGPoint]
    var rightBrowPoints: [CGPoint]
    var nosePoints: [CGPoint]
    var expressionConfidence: Float
    var blendshapeCoefficients: [String: Float]

    static let neutral = FaceLandmarks(
        boundingBox: .zero,
        mouthOpen: 0,
        jawOpen: 0,
        mouthWidth: 0,
        lipPucker: 0,
        leftEyeBlink: 0,
        rightEyeBlink: 0,
        leftEyeOpen: 0,
        rightEyeOpen: 0,
        leftBrowRaise: 0,
        rightBrowRaise: 0,
        gazeX: 0,
        gazeY: 0,
        headEulerAngles: .zero,
        normalizedPoints: [],
        faceContourPoints: [],
        mouthOuterPoints: [],
        leftEyePoints: [],
        rightEyePoints: [],
        leftBrowPoints: [],
        rightBrowPoints: [],
        nosePoints: [],
        expressionConfidence: 0,
        blendshapeCoefficients: [:]
    )
}
