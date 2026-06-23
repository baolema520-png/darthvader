import AVFoundation
import CoreGraphics
import Foundation
import Vision

struct VisionFaceLandmarkExtractor {
    func extract(
        from pixelBuffer: CVPixelBuffer,
        sequenceRequestHandler: VNSequenceRequestHandler
    ) throws -> FaceLandmarks? {
        let request = VNDetectFaceLandmarksRequest()
        try sequenceRequestHandler.perform([request], on: pixelBuffer)
        guard let observation = request.results?.first else { return nil }

        let metrics = Self.extractMetrics(from: observation)
        let contourPoints = Self.globalPoints(from: observation.landmarks?.faceContour, in: observation.boundingBox)
        let mouthOuterPoints = Self.globalPoints(from: observation.landmarks?.outerLips, in: observation.boundingBox)
        let leftEyePoints = Self.globalPoints(from: observation.landmarks?.leftEye, in: observation.boundingBox)
        let rightEyePoints = Self.globalPoints(from: observation.landmarks?.rightEye, in: observation.boundingBox)
        let leftBrowPoints = Self.globalPoints(from: observation.landmarks?.leftEyebrow, in: observation.boundingBox)
        let rightBrowPoints = Self.globalPoints(from: observation.landmarks?.rightEyebrow, in: observation.boundingBox)
        let nosePoints = Self.globalPoints(from: observation.landmarks?.nose, in: observation.boundingBox)

        return FaceLandmarks(
            boundingBox: observation.boundingBox,
            mouthOpen: metrics.mouthOpen,
            jawOpen: metrics.jawOpen,
            mouthWidth: metrics.mouthWidth,
            lipPucker: metrics.lipPucker,
            leftEyeBlink: metrics.leftEyeBlink,
            rightEyeBlink: metrics.rightEyeBlink,
            leftEyeOpen: metrics.leftEyeOpen,
            rightEyeOpen: metrics.rightEyeOpen,
            leftBrowRaise: metrics.leftBrowRaise,
            rightBrowRaise: metrics.rightBrowRaise,
            gazeX: metrics.gazeX,
            gazeY: metrics.gazeY,
            headEulerAngles: metrics.headEulerAngles,
            normalizedPoints: Self.flattenedPoints(from: observation.landmarks),
            faceContourPoints: contourPoints,
            mouthOuterPoints: mouthOuterPoints,
            leftEyePoints: leftEyePoints,
            rightEyePoints: rightEyePoints,
            leftBrowPoints: leftBrowPoints,
            rightBrowPoints: rightBrowPoints,
            nosePoints: nosePoints,
            expressionConfidence: metrics.expressionConfidence,
            blendshapeCoefficients: MediaPipeBlendshapeMapper.makeBlendshapeSet(
                jawOpen: metrics.jawOpen,
                mouthOpen: metrics.mouthOpen,
                mouthWidth: metrics.mouthWidth,
                lipPucker: metrics.lipPucker,
                leftEyeBlink: metrics.leftEyeBlink,
                rightEyeBlink: metrics.rightEyeBlink,
                leftEyeOpen: metrics.leftEyeOpen,
                rightEyeOpen: metrics.rightEyeOpen,
                leftBrowRaise: metrics.leftBrowRaise,
                rightBrowRaise: metrics.rightBrowRaise,
                gazeX: metrics.gazeX,
                gazeY: metrics.gazeY,
                external: [:]
            )
        )
    }
}

private extension VisionFaceLandmarkExtractor {
    static func flattenedPoints(from landmarks: VNFaceLandmarks2D?) -> [CGPoint] {
        guard let landmarks else { return [] }
        let allRegions: [VNFaceLandmarkRegion2D?] = [
            landmarks.faceContour,
            landmarks.leftEye, landmarks.rightEye,
            landmarks.leftEyebrow, landmarks.rightEyebrow,
            landmarks.nose,
            landmarks.outerLips, landmarks.innerLips,
            landmarks.medianLine
        ]

        return allRegions.compactMap { $0 }.flatMap { region in
            (0..<region.pointCount).map { i in
                let p = region.normalizedPoints[i]
                return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
            }
        }
    }

    static func extractMetrics(from observation: VNFaceObservation) -> (
        mouthOpen: Float,
        jawOpen: Float,
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
        headEulerAngles: simd_float3,
        expressionConfidence: Float
    ) {
        guard let landmarks = observation.landmarks else {
            return (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, .zero, 0)
        }

        let bbox = observation.boundingBox
        let innerLips = globalPoints(from: landmarks.innerLips, in: bbox)
        let outerLips = globalPoints(from: landmarks.outerLips, in: bbox)
        let leftEye = globalPoints(from: landmarks.leftEye, in: bbox)
        let rightEye = globalPoints(from: landmarks.rightEye, in: bbox)
        let leftBrow = globalPoints(from: landmarks.leftEyebrow, in: bbox)
        let rightBrow = globalPoints(from: landmarks.rightEyebrow, in: bbox)
        let nose = globalPoints(from: landmarks.nose, in: bbox)

        let faceHeight = max(bbox.height, 0.0001)
        let mouthOpen = normalizedMouthOpen(innerLips: innerLips, faceHeight: faceHeight)
        let jawOpen = normalizedJawOpen(innerLips: innerLips, outerLips: outerLips, faceHeight: faceHeight)
        let mouthWidth = normalizedMouthWidth(outerLips: outerLips, faceHeight: faceHeight)
        let lipPucker = normalizedLipPucker(innerLips: innerLips, outerLips: outerLips, faceHeight: faceHeight)
        let leftEyeOpen = normalizedEyeOpen(eyePoints: leftEye, faceHeight: faceHeight)
        let rightEyeOpen = normalizedEyeOpen(eyePoints: rightEye, faceHeight: faceHeight)
        let leftEyeBlink = clamp01(1 - leftEyeOpen)
        let rightEyeBlink = clamp01(1 - rightEyeOpen)
        let leftBrowRaise = normalizedBrowRaise(brow: leftBrow, eye: leftEye, faceHeight: faceHeight)
        let rightBrowRaise = normalizedBrowRaise(brow: rightBrow, eye: rightEye, faceHeight: faceHeight)
        let gaze = estimateGaze(leftEye: leftEye, rightEye: rightEye, nose: nose, faceHeight: faceHeight)
        let headEuler = estimateHeadEuler(leftEye: leftEye, rightEye: rightEye, nose: nose)
        let expressionConfidence = confidence(
            innerLips: innerLips,
            outerLips: outerLips,
            leftEye: leftEye,
            rightEye: rightEye,
            faceHeight: faceHeight
        )

        return (
            mouthOpen: mouthOpen,
            jawOpen: jawOpen,
            mouthWidth: mouthWidth,
            lipPucker: lipPucker,
            leftEyeBlink: leftEyeBlink,
            rightEyeBlink: rightEyeBlink,
            leftEyeOpen: leftEyeOpen,
            rightEyeOpen: rightEyeOpen,
            leftBrowRaise: leftBrowRaise,
            rightBrowRaise: rightBrowRaise,
            gazeX: Float(gaze.x),
            gazeY: Float(gaze.y),
            headEulerAngles: headEuler,
            expressionConfidence: expressionConfidence
        )
    }

    static func globalPoints(from region: VNFaceLandmarkRegion2D?, in bbox: CGRect) -> [CGPoint] {
        guard let region else { return [] }
        return (0..<region.pointCount).map { index in
            let p = region.normalizedPoints[index]
            return CGPoint(
                x: bbox.origin.x + CGFloat(p.x) * bbox.width,
                y: bbox.origin.y + CGFloat(p.y) * bbox.height
            )
        }
    }

    static func normalizedMouthOpen(innerLips: [CGPoint], faceHeight: CGFloat) -> Float {
        guard innerLips.count >= 4 else { return 0 }
        let ys = innerLips.map(\.y)
        let open = (ys.max() ?? 0) - (ys.min() ?? 0)
        return clamp01(Float((open / faceHeight) * 8))
    }

    static func normalizedEyeOpen(eyePoints: [CGPoint], faceHeight: CGFloat) -> Float {
        guard eyePoints.count >= 4 else { return 0 }
        let ys = eyePoints.map(\.y)
        let open = (ys.max() ?? 0) - (ys.min() ?? 0)
        return clamp01(Float((open / faceHeight) * 14))
    }

    static func normalizedJawOpen(innerLips: [CGPoint], outerLips: [CGPoint], faceHeight: CGFloat) -> Float {
        let base = normalizedMouthOpen(innerLips: innerLips, faceHeight: faceHeight)
        guard !outerLips.isEmpty else { return base }
        let outerOpen = (outerLips.map(\.y).max() ?? 0) - (outerLips.map(\.y).min() ?? 0)
        let normalizedOuter = clamp01(Float((outerOpen / faceHeight) * 6))
        return clamp01(base * 0.6 + normalizedOuter * 0.4)
    }

    static func normalizedMouthWidth(outerLips: [CGPoint], faceHeight: CGFloat) -> Float {
        guard !outerLips.isEmpty else { return 0.5 }
        let xs = outerLips.map(\.x)
        let width = (xs.max() ?? 0) - (xs.min() ?? 0)
        let normalized = Float((width / faceHeight) * 2.3)
        return clamp01(normalized)
    }

    static func normalizedLipPucker(innerLips: [CGPoint], outerLips: [CGPoint], faceHeight: CGFloat) -> Float {
        guard !innerLips.isEmpty, !outerLips.isEmpty else { return 0 }
        let innerXs = innerLips.map(\.x)
        let outerXs = outerLips.map(\.x)
        let innerWidth = (innerXs.max() ?? 0) - (innerXs.min() ?? 0)
        let outerWidth = (outerXs.max() ?? 0) - (outerXs.min() ?? 0)
        guard outerWidth > 0.0001 else { return 0 }
        let ratio = innerWidth / outerWidth
        return clamp01(Float((1 - ratio) * 2.2))
    }

    static func normalizedBrowRaise(brow: [CGPoint], eye: [CGPoint], faceHeight: CGFloat) -> Float {
        guard !brow.isEmpty, !eye.isEmpty else { return 0 }
        let browY = brow.map(\.y).reduce(0, +) / CGFloat(brow.count)
        let eyeY = eye.map(\.y).reduce(0, +) / CGFloat(eye.count)
        let delta = browY - eyeY
        return clamp01(Float((delta / faceHeight) * 10))
    }

    static func estimateHeadEuler(leftEye: [CGPoint], rightEye: [CGPoint], nose: [CGPoint]) -> simd_float3 {
        guard !leftEye.isEmpty, !rightEye.isEmpty else { return .zero }
        let leftCenter = centroid(leftEye)
        let rightCenter = centroid(rightEye)
        let eyeMid = CGPoint(x: (leftCenter.x + rightCenter.x) * 0.5, y: (leftCenter.y + rightCenter.y) * 0.5)
        let interocular = max(distance(leftCenter, rightCenter), 0.0001)
        let roll = Float(atan2(Double(rightCenter.y - leftCenter.y), Double(rightCenter.x - leftCenter.x)))
        let noseCenter = nose.isEmpty ? eyeMid : centroid(nose)
        let yaw = Float((noseCenter.x - eyeMid.x) / interocular)
        let pitch = Float((noseCenter.y - eyeMid.y) / interocular)
        return simd_float3(pitch, yaw, roll)
    }

    static func estimateGaze(leftEye: [CGPoint], rightEye: [CGPoint], nose: [CGPoint], faceHeight: CGFloat) -> CGPoint {
        guard !leftEye.isEmpty, !rightEye.isEmpty else { return .zero }
        let leftCenter = centroid(leftEye)
        let rightCenter = centroid(rightEye)
        let eyeMid = CGPoint(x: (leftCenter.x + rightCenter.x) * 0.5, y: (leftCenter.y + rightCenter.y) * 0.5)
        let noseCenter = nose.isEmpty ? eyeMid : centroid(nose)
        let interocular = max(distance(leftCenter, rightCenter), 0.0001)
        let gx = clampSigned(Float((noseCenter.x - eyeMid.x) / interocular) * 1.6)
        let gy = clampSigned(Float((eyeMid.y - noseCenter.y) / max(faceHeight, 0.0001)) * 8.0)
        return CGPoint(x: CGFloat(gx), y: CGFloat(gy))
    }

    static func confidence(
        innerLips: [CGPoint],
        outerLips: [CGPoint],
        leftEye: [CGPoint],
        rightEye: [CGPoint],
        faceHeight: CGFloat
    ) -> Float {
        let validRegions = [innerLips, outerLips, leftEye, rightEye].filter { !$0.isEmpty }.count
        let coverage = Float(validRegions) / 4
        let eyeScale = (normalizedEyeOpen(eyePoints: leftEye, faceHeight: faceHeight) +
            normalizedEyeOpen(eyePoints: rightEye, faceHeight: faceHeight)) * 0.5
        return clamp01(coverage * 0.7 + eyeScale * 0.3)
    }

    static func centroid(_ points: [CGPoint]) -> CGPoint {
        let x = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let y = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        return CGPoint(x: x, y: y)
    }

    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    static func clamp01(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    static func clampSigned(_ value: Float) -> Float {
        min(max(value, -1), 1)
    }
}
