import Foundation

struct MediaPipeBlendshapeMapper {
    static func makeBlendshapeSet(
        jawOpen: Float,
        mouthOpen: Float,
        mouthWidth: Float,
        lipPucker: Float,
        leftEyeBlink: Float,
        rightEyeBlink: Float,
        leftEyeOpen: Float,
        rightEyeOpen: Float,
        leftBrowRaise: Float,
        rightBrowRaise: Float,
        gazeX: Float,
        gazeY: Float,
        external: [String: Float]
    ) -> [String: Float] {
        var mapped: [String: Float] = Dictionary(uniqueKeysWithValues: BlendshapeCatalog.names.map { ($0, Float(0)) })

        mapped["jawOpen"] = clamp01(max(jawOpen, mouthOpen))
        mapped["mouthClose"] = clamp01(1 - mouthOpen)
        mapped["mouthPucker"] = clamp01(lipPucker)
        mapped["mouthFunnel"] = clamp01(lipPucker * 0.8 + mouthOpen * 0.2)
        mapped["mouthSmileLeft"] = clamp01(max(0, mouthWidth - 0.45) * 1.7)
        mapped["mouthSmileRight"] = clamp01(max(0, mouthWidth - 0.45) * 1.7)
        mapped["mouthFrownLeft"] = clamp01(max(0, 0.45 - mouthWidth) * 1.8)
        mapped["mouthFrownRight"] = clamp01(max(0, 0.45 - mouthWidth) * 1.8)
        mapped["mouthStretchLeft"] = clamp01(max(0, mouthWidth - 0.5) * 1.4)
        mapped["mouthStretchRight"] = clamp01(max(0, mouthWidth - 0.5) * 1.4)
        mapped["mouthRollLower"] = clamp01(jawOpen * 0.4 + lipPucker * 0.3)
        mapped["mouthRollUpper"] = clamp01(mouthOpen * 0.35 + lipPucker * 0.2)
        mapped["mouthPressLeft"] = clamp01((1 - mouthOpen) * 0.45)
        mapped["mouthPressRight"] = clamp01((1 - mouthOpen) * 0.45)
        mapped["mouthUpperUpLeft"] = clamp01(mouthOpen * 0.65)
        mapped["mouthUpperUpRight"] = clamp01(mouthOpen * 0.65)
        mapped["mouthLowerDownLeft"] = clamp01(jawOpen * 0.8)
        mapped["mouthLowerDownRight"] = clamp01(jawOpen * 0.8)

        mapped["eyeBlinkLeft"] = clamp01(leftEyeBlink)
        mapped["eyeBlinkRight"] = clamp01(rightEyeBlink)
        mapped["eyeWideLeft"] = clamp01(leftEyeOpen * 0.9)
        mapped["eyeWideRight"] = clamp01(rightEyeOpen * 0.9)
        mapped["eyeSquintLeft"] = clamp01(leftEyeBlink * 0.8)
        mapped["eyeSquintRight"] = clamp01(rightEyeBlink * 0.8)

        mapped["browOuterUpLeft"] = clamp01(leftBrowRaise)
        mapped["browOuterUpRight"] = clamp01(rightBrowRaise)
        mapped["browInnerUp"] = clamp01((leftBrowRaise + rightBrowRaise) * 0.5)
        mapped["browDownLeft"] = clamp01(max(0, 0.3 - leftBrowRaise))
        mapped["browDownRight"] = clamp01(max(0, 0.3 - rightBrowRaise))

        mapped["eyeLookOutLeft"] = clamp01(max(0, gazeX))
        mapped["eyeLookInLeft"] = clamp01(max(0, -gazeX))
        mapped["eyeLookOutRight"] = clamp01(max(0, -gazeX))
        mapped["eyeLookInRight"] = clamp01(max(0, gazeX))
        mapped["eyeLookUpLeft"] = clamp01(max(0, gazeY))
        mapped["eyeLookUpRight"] = clamp01(max(0, gazeY))
        mapped["eyeLookDownLeft"] = clamp01(max(0, -gazeY))
        mapped["eyeLookDownRight"] = clamp01(max(0, -gazeY))

        for (key, value) in external where mapped.keys.contains(key) {
            // If an external MediaPipe provider is present, prioritize it.
            mapped[key] = clamp01(value)
        }
        return mapped
    }

    private static func clamp01(_ v: Float) -> Float {
        min(max(v, 0), 1)
    }
}
