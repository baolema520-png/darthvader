import Foundation

struct ExpressionRigFrame: Sendable, Equatable {
    var jawOpen: Float
    var mouthOpen: Float
    var mouthWidth: Float
    var lipPucker: Float
    var leftEyeBlink: Float
    var rightEyeBlink: Float
    var leftBrowRaise: Float
    var rightBrowRaise: Float
    var gazeX: Float
    var gazeY: Float
    var headYaw: Float
    var headPitch: Float
    var headRoll: Float
    var confidence: Float

    // Subconjunto semantico compatible estilo ARKit (52-style naming subset).
    var semanticBlendshapes: [String: Float] {
        [
            "jawOpen": jawOpen,
            "mouthOpen": mouthOpen,
            "mouthPucker": lipPucker,
            "mouthSmileLeft": max(0, mouthWidth * 0.5),
            "mouthSmileRight": max(0, mouthWidth * 0.5),
            "eyeBlinkLeft": leftEyeBlink,
            "eyeBlinkRight": rightEyeBlink,
            "browOuterUpLeft": max(0, leftBrowRaise),
            "browOuterUpRight": max(0, rightBrowRaise),
            "eyeLookOutLeft": max(0, gazeX),
            "eyeLookInRight": max(0, gazeX),
            "eyeLookDownLeft": max(0, -gazeY),
            "eyeLookDownRight": max(0, -gazeY)
        ]
    }
}
