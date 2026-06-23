import CoreGraphics
import Foundation
import simd

final class AvatarEngine: AvatarEngineProviding {
    private struct CalibrationProfile: Sendable {
        var jawNeutral: Float
        var mouthOpenNeutral: Float
        var mouthWidthNeutral: Float
        var lipPuckerNeutral: Float
        var leftEyeBlinkNeutral: Float
        var rightEyeBlinkNeutral: Float
        var jawRange: Float
        var mouthOpenRange: Float
        var mouthWidthRange: Float
        var lipPuckerRange: Float
        var leftEyeBlinkRange: Float
        var rightEyeBlinkRange: Float
    }

    private(set) var avatarModel: AvatarModel?

    private let preprocessor: AvatarPreprocessor
    private let meshGenerator: MeshGenerator
    private let fittingService: CanonicalAvatarFittingService
    private let proceduralTextureGenerator: ProceduralIdentityTextureGenerator
    private var neutralLandmarks: FaceLandmarks?
    private var lastOutputMesh: AvatarMesh?
    private var canonicalRig: CanonicalBlendshapeRig = .empty
    private var mouthSensitivity: Float = 1.0
    private var eyeSensitivity: Float = 1.0
    private var smoothingFactor: Float = 0.65
    private var fitResult: CanonicalAvatarFitResult?
    private var calibrationSamples: [FaceLandmarks] = []
    private var calibrationProfile: CalibrationProfile?
    private var faceWidthOverride: Float = 1.0
    private var jawWidthOverride: Float = 1.0
    private var eyeSpacingOverride: Float = 1.0
    private var noseWidthOverride: Float = 1.0
    private var mouthWidthOverride: Float = 1.0
    private var lastProceduralTextureSignature: String?

    init(
        preprocessor: AvatarPreprocessor = AvatarPreprocessor(),
        meshGenerator: MeshGenerator = MeshGenerator(),
        fittingService: CanonicalAvatarFittingService = CanonicalAvatarFittingService(),
        proceduralTextureGenerator: ProceduralIdentityTextureGenerator = ProceduralIdentityTextureGenerator()
    ) {
        self.preprocessor = preprocessor
        self.meshGenerator = meshGenerator
        self.fittingService = fittingService
        self.proceduralTextureGenerator = proceduralTextureGenerator
    }

    func loadAvatar(from imageURL: URL) async throws {
        let result = try preprocessor.preprocess(imageURL: imageURL)
        fitResult = fittingService.runBuiltInFitting(preprocess: result)
        let mesh = meshGenerator.generateMesh(from: result.normalizedLandmarks)
        let segmentedIndices = segmentVertices(mesh: mesh, regionPoints: result.regionPoints)
        let vertexLandmarkMap = buildVertexLandmarkMap(vertices: mesh.vertices, landmarks: result.normalizedLandmarks)
        let regionLandmarkIndices = buildRegionLandmarkIndices(
            referenceLandmarks: result.normalizedLandmarks,
            regionPoints: result.regionPoints
        )
        avatarModel = AvatarModel(
            texturePath: result.texturePath,
            mesh: mesh,
            referenceLandmarks: result.normalizedLandmarks,
            vertexLandmarkMap: vertexLandmarkMap,
            segmentedRegionVertexIndices: segmentedIndices,
            regionLandmarkIndices: regionLandmarkIndices,
            featureAnchors: result.featureAnchors,
            identityMetadata: fitResult?.identityMetadata ?? [:]
        )
        canonicalRig = buildCanonicalRig(from: mesh, segmentedIndices: segmentedIndices, fitResult: fitResult)
        lastOutputMesh = mesh
        neutralLandmarks = nil
    }

    func animateAvatar(with landmarks: FaceLandmarks?) -> AvatarMesh? {
        guard let avatarModel else { return nil }
        guard let landmarks else { return avatarModel.mesh }
        if neutralLandmarks == nil { neutralLandmarks = landmarks }
        guard let neutralLandmarks else { return avatarModel.mesh }
        let confidence = max(0.72, landmarks.expressionConfidence)
        let rig = buildRig(current: landmarks, neutral: neutralLandmarks, confidence: confidence)

        var deformed = avatarModel.mesh
        applyIdentityMorph(to: &deformed, avatarModel: avatarModel)
        let mouthLandmarks = Set(avatarModel.regionLandmarkIndices[.mouth] ?? [])
        let leftEyeLandmarks = Set(avatarModel.regionLandmarkIndices[.leftEye] ?? [])
        let rightEyeLandmarks = Set(avatarModel.regionLandmarkIndices[.rightEye] ?? [])
        let mouthVertices = expandedVertexRegion(
            verticesLinked(toLandmarks: mouthLandmarks, vertexMap: avatarModel.vertexLandmarkMap),
            in: avatarModel.mesh,
            radius: 0.06
        )
        let leftEyeVertices = expandedVertexRegion(
            verticesLinked(toLandmarks: leftEyeLandmarks, vertexMap: avatarModel.vertexLandmarkMap),
            in: avatarModel.mesh,
            radius: 0.045
        )
        let rightEyeVertices = expandedVertexRegion(
            verticesLinked(toLandmarks: rightEyeLandmarks, vertexMap: avatarModel.vertexLandmarkMap),
            in: avatarModel.mesh,
            radius: 0.045
        )
        // Paso semantico principal: deforma subregiones por transformaciones de landmarks.
        applyRegionDrivenDeformation(
            to: &deformed,
            vertexIndices: mouthVertices,
            referenceLandmarks: avatarModel.referenceLandmarks,
            liveLandmarks: landmarks.normalizedPoints,
            landmarkIndices: avatarModel.regionLandmarkIndices[.mouth] ?? [],
            strength: 0.72,
            clampScaleX: (0.82, 1.22),
            clampScaleY: (0.55, 2.25)
        )
        applyRegionDrivenDeformation(
            to: &deformed,
            vertexIndices: leftEyeVertices,
            referenceLandmarks: avatarModel.referenceLandmarks,
            liveLandmarks: landmarks.normalizedPoints,
            landmarkIndices: avatarModel.regionLandmarkIndices[.leftEye] ?? [],
            strength: 0.68,
            clampScaleX: (0.86, 1.12),
            clampScaleY: (0.06, 1.16)
        )
        applyRegionDrivenDeformation(
            to: &deformed,
            vertexIndices: rightEyeVertices,
            referenceLandmarks: avatarModel.referenceLandmarks,
            liveLandmarks: landmarks.normalizedPoints,
            landmarkIndices: avatarModel.regionLandmarkIndices[.rightEye] ?? [],
            strength: 0.68,
            clampScaleX: (0.86, 1.12),
            clampScaleY: (0.06, 1.16)
        )
        applyLandmarkMotion(
            to: &deformed,
            referenceLandmarks: avatarModel.referenceLandmarks,
            liveLandmarks: landmarks.normalizedPoints,
            vertexMap: avatarModel.vertexLandmarkMap,
            confidence: confidence
        )
        canonicalRig.apply(
            to: &deformed,
            coefficients: landmarks.blendshapeCoefficients,
            confidence: confidence
        )
        applyMouth(
            to: &deformed,
            indices: mouthVertices,
            jawOpen: rig.jawOpen,
            mouthWidth: rig.mouthWidth,
            lipPucker: rig.lipPucker
        )
        applyEyeGaze(
            to: &deformed,
            indices: leftEyeVertices,
            gazeX: rig.gazeX,
            gazeY: rig.gazeY
        )
        applyEyeGaze(
            to: &deformed,
            indices: rightEyeVertices,
            gazeX: rig.gazeX,
            gazeY: rig.gazeY
        )
        applyEyeBlink(
            to: &deformed,
            indices: leftEyeVertices,
            blink: rig.leftEyeBlink
        )
        applyEyeBlink(
            to: &deformed,
            indices: rightEyeVertices,
            blink: rig.rightEyeBlink
        )
        applyBrow(to: &deformed, indices: avatarModel.segmentedRegionVertexIndices[.leftBrow] ?? [], delta: rig.leftBrowRaise)
        applyBrow(to: &deformed, indices: avatarModel.segmentedRegionVertexIndices[.rightBrow] ?? [], delta: rig.rightBrowRaise)
        applyHeadTransform(to: &deformed, roll: rig.headRoll, yaw: rig.headYaw, pitch: rig.headPitch)

        if let lastOutputMesh {
            deformed = smooth(current: deformed, previous: lastOutputMesh, factor: smoothingFactor)
        }
        lastOutputMesh = deformed
        return deformed
    }

    func updateParameters(mouthSensitivity: Float, eyeSensitivity: Float, smoothing: Float) {
        self.mouthSensitivity = mouthSensitivity
        self.eyeSensitivity = eyeSensitivity
        self.smoothingFactor = min(max(smoothing, 0), 0.95)
    }

    func updateIdentityParameters(
        faceWidth: Float,
        jawWidth: Float,
        eyeSpacing: Float,
        noseWidth: Float,
        mouthWidth: Float
    ) {
        self.faceWidthOverride = faceWidth
        self.jawWidthOverride = jawWidth
        self.eyeSpacingOverride = eyeSpacing
        self.noseWidthOverride = noseWidth
        self.mouthWidthOverride = mouthWidth
        guard var model = avatarModel else { return }
        model.identityMetadata["faceWidthScale"] = faceWidth
        model.identityMetadata["jawWidthScale"] = jawWidth
        model.identityMetadata["eyeSpacingScale"] = eyeSpacing
        model.identityMetadata["noseWidthScale"] = noseWidth
        model.identityMetadata["mouthWidthScale"] = mouthWidth
        model.identityMetadata["mouthScale"] = mouthWidth
        if (model.identityMetadata["derivedIdentity"] ?? 0) > 0.5 {
            model.identityMetadata["useLiveTexture"] = 0
            let signature = proceduralTextureSignature(
                faceWidth: faceWidth,
                jawWidth: jawWidth,
                eyeSpacing: eyeSpacing,
                noseWidth: noseWidth,
                mouthWidth: mouthWidth
            )
            if signature != lastProceduralTextureSignature {
                if let updatedURL = try? proceduralTextureGenerator.generateTexture(
                    featureAnchors: model.featureAnchors,
                    identityMetadata: model.identityMetadata,
                    sourceLandmarks: neutralLandmarks ?? .neutral,
                    existingURL: model.texturePath.path == "/dev/null" ? nil : model.texturePath
                ) {
                    model.texturePath = updatedURL
                    lastProceduralTextureSignature = signature
                }
            }
        }
        avatarModel = model
    }

    func beginCalibration() {
        calibrationSamples.removeAll(keepingCapacity: true)
        calibrationProfile = nil
        neutralLandmarks = nil
    }

    func ingestCalibrationSample(_ landmarks: FaceLandmarks) {
        if calibrationSamples.count >= 90 {
            calibrationSamples.removeFirst(calibrationSamples.count - 89)
        }
        calibrationSamples.append(landmarks)
    }

    func finishCalibration() {
        guard !calibrationSamples.isEmpty else { return }
        let samples = calibrationSamples
        calibrationSamples.removeAll(keepingCapacity: true)

        func avg(_ values: [Float]) -> Float {
            guard !values.isEmpty else { return 0 }
            return values.reduce(0, +) / Float(values.count)
        }
        func range(_ values: [Float], floor: Float) -> Float {
            guard let minV = values.min(), let maxV = values.max() else { return floor }
            return max(floor, maxV - minV)
        }

        let jaws = samples.map(\.jawOpen)
        let mouths = samples.map(\.mouthOpen)
        let widths = samples.map(\.mouthWidth)
        let puckers = samples.map(\.lipPucker)
        let leftBlinks = samples.map(\.leftEyeBlink)
        let rightBlinks = samples.map(\.rightEyeBlink)

        calibrationProfile = CalibrationProfile(
            jawNeutral: avg(jaws),
            mouthOpenNeutral: avg(mouths),
            mouthWidthNeutral: avg(widths),
            lipPuckerNeutral: avg(puckers),
            leftEyeBlinkNeutral: avg(leftBlinks),
            rightEyeBlinkNeutral: avg(rightBlinks),
            jawRange: range(jaws, floor: 0.18),
            mouthOpenRange: range(mouths, floor: 0.14),
            mouthWidthRange: range(widths, floor: 0.10),
            lipPuckerRange: range(puckers, floor: 0.10),
            leftEyeBlinkRange: range(leftBlinks, floor: 0.12),
            rightEyeBlinkRange: range(rightBlinks, floor: 0.12)
        )
        buildDerivedIdentityModel(from: samples)
    }

    func resetNeutralPose() {
        neutralLandmarks = nil
        lastOutputMesh = avatarModel?.mesh
    }
}

private extension AvatarEngine {
    func buildDerivedIdentityModel(from samples: [FaceLandmarks]) {
        guard let averaged = averageCalibrationSample(samples), averaged.normalizedPoints.count >= 12 else { return }
        let mesh = meshGenerator.generateMesh(from: averaged.normalizedPoints)
        let regionPoints = derivedRegionPoints(from: averaged)
        let segmentedIndices = segmentVertices(mesh: mesh, regionPoints: regionPoints)
        let vertexLandmarkMap = buildVertexLandmarkMap(vertices: mesh.vertices, landmarks: averaged.normalizedPoints)
        let regionLandmarkIndices = buildRegionLandmarkIndices(
            referenceLandmarks: averaged.normalizedPoints,
            regionPoints: regionPoints
        )
        let derivedAnchors = featureAnchors(from: averaged)
        let derivedMetadata = makeDerivedIdentityMetadata(from: averaged)
        let textureURL = (try? proceduralTextureGenerator.generateTexture(
            featureAnchors: derivedAnchors,
            identityMetadata: derivedMetadata,
            sourceLandmarks: averaged
        )) ?? URL(fileURLWithPath: "/dev/null")
        avatarModel = AvatarModel(
            texturePath: textureURL,
            mesh: mesh,
            referenceLandmarks: averaged.normalizedPoints,
            vertexLandmarkMap: vertexLandmarkMap,
            segmentedRegionVertexIndices: segmentedIndices,
            regionLandmarkIndices: regionLandmarkIndices,
            featureAnchors: derivedAnchors,
            identityMetadata: derivedMetadata
        )
        canonicalRig = buildCanonicalRig(from: mesh, segmentedIndices: segmentedIndices, fitResult: nil)
        lastOutputMesh = mesh
        neutralLandmarks = averaged
        lastProceduralTextureSignature = proceduralTextureSignature(
            faceWidth: faceWidthOverride,
            jawWidth: jawWidthOverride,
            eyeSpacing: eyeSpacingOverride,
            noseWidth: noseWidthOverride,
            mouthWidth: mouthWidthOverride
        )
    }

    func proceduralTextureSignature(
        faceWidth: Float,
        jawWidth: Float,
        eyeSpacing: Float,
        noseWidth: Float,
        mouthWidth: Float
    ) -> String {
        [
            Int(faceWidth * 1000),
            Int(jawWidth * 1000),
            Int(eyeSpacing * 1000),
            Int(noseWidth * 1000),
            Int(mouthWidth * 1000)
        ].map(String.init).joined(separator: "_")
    }

    func averageCalibrationSample(_ samples: [FaceLandmarks]) -> FaceLandmarks? {
        guard let first = samples.first else { return nil }
        func averagePoints(_ keyPath: KeyPath<FaceLandmarks, [CGPoint]>) -> [CGPoint] {
            let arrays = samples.map { $0[keyPath: keyPath] }
            guard let count = arrays.first?.count, count > 0, arrays.allSatisfy({ $0.count == count }) else {
                return first[keyPath: keyPath]
            }
            return (0..<count).map { index in
                CGPoint(
                    x: arrays.map { $0[index].x }.reduce(0, +) / CGFloat(arrays.count),
                    y: arrays.map { $0[index].y }.reduce(0, +) / CGFloat(arrays.count)
                )
            }
        }
        func averageFloat(_ keyPath: KeyPath<FaceLandmarks, Float>) -> Float {
            samples.map { $0[keyPath: keyPath] }.reduce(0, +) / Float(samples.count)
        }
        let boxes = samples.map(\.boundingBox)
        let bbox = CGRect(
            x: boxes.map(\.origin.x).reduce(0, +) / CGFloat(boxes.count),
            y: boxes.map(\.origin.y).reduce(0, +) / CGFloat(boxes.count),
            width: boxes.map(\.width).reduce(0, +) / CGFloat(boxes.count),
            height: boxes.map(\.height).reduce(0, +) / CGFloat(boxes.count)
        )
        return FaceLandmarks(
            boundingBox: bbox,
            mouthOpen: averageFloat(\.mouthOpen),
            jawOpen: averageFloat(\.jawOpen),
            mouthWidth: averageFloat(\.mouthWidth),
            lipPucker: averageFloat(\.lipPucker),
            leftEyeBlink: averageFloat(\.leftEyeBlink),
            rightEyeBlink: averageFloat(\.rightEyeBlink),
            leftEyeOpen: averageFloat(\.leftEyeOpen),
            rightEyeOpen: averageFloat(\.rightEyeOpen),
            leftBrowRaise: averageFloat(\.leftBrowRaise),
            rightBrowRaise: averageFloat(\.rightBrowRaise),
            gazeX: averageFloat(\.gazeX),
            gazeY: averageFloat(\.gazeY),
            headEulerAngles: samples.map(\.headEulerAngles).reduce(simd_float3.zero, +) / Float(samples.count),
            normalizedPoints: averagePoints(\.normalizedPoints),
            faceContourPoints: averagePoints(\.faceContourPoints),
            mouthOuterPoints: averagePoints(\.mouthOuterPoints),
            leftEyePoints: averagePoints(\.leftEyePoints),
            rightEyePoints: averagePoints(\.rightEyePoints),
            leftBrowPoints: averagePoints(\.leftBrowPoints),
            rightBrowPoints: averagePoints(\.rightBrowPoints),
            nosePoints: averagePoints(\.nosePoints),
            expressionConfidence: averageFloat(\.expressionConfidence),
            blendshapeCoefficients: samples.last?.blendshapeCoefficients ?? [:]
        )
    }

    func derivedRegionPoints(from landmarks: FaceLandmarks) -> [AvatarRegion: [CGPoint]] {
        [
            .mouth: landmarks.mouthOuterPoints,
            .leftEye: landmarks.leftEyePoints,
            .rightEye: landmarks.rightEyePoints,
            .leftBrow: landmarks.leftBrowPoints,
            .rightBrow: landmarks.rightBrowPoints,
            .nose: landmarks.nosePoints,
            .jawline: landmarks.faceContourPoints
        ]
    }

    func featureAnchors(from landmarks: FaceLandmarks) -> AvatarFeatureAnchors {
        let mouthBounds = boundingBox(of: landmarks.mouthOuterPoints)
        return AvatarFeatureAnchors(
            leftEyeCenter: centroid(of: landmarks.leftEyePoints),
            rightEyeCenter: centroid(of: landmarks.rightEyePoints),
            mouthCenter: centroid(of: landmarks.mouthOuterPoints),
            mouthSize: CGSize(width: mouthBounds.width, height: mouthBounds.height)
        )
    }

    func makeDerivedIdentityMetadata(from landmarks: FaceLandmarks) -> [String: Float] {
        let faceBounds = boundingBox(of: landmarks.faceContourPoints)
        let eyeSpacing = distance(centroid(of: landmarks.leftEyePoints), centroid(of: landmarks.rightEyePoints))
        let leftEyeBounds = boundingBox(of: landmarks.leftEyePoints)
        let rightEyeBounds = boundingBox(of: landmarks.rightEyePoints)
        let averageEyeWidth = (leftEyeBounds.width + rightEyeBounds.width) * 0.5
        let averageEyeHeight = (leftEyeBounds.height + rightEyeBounds.height) * 0.5
        let mouthBounds = boundingBox(of: landmarks.mouthOuterPoints)
        let noseBounds = boundingBox(of: landmarks.nosePoints)
        func mirrored(_ normalized: CGFloat, baseShift: CGFloat, min minValue: CGFloat, max maxValue: CGFloat) -> Float {
            var value = 1 - (normalized - 1) * 0.82
            if abs(value - 1) < 0.05 {
                value += normalized >= 1 ? -baseShift : baseShift
            }
            return Float(min(max(value, minValue), maxValue))
        }
        let normalizedEyeSpacing = eyeSpacing / max(faceBounds.width, 0.0001) / 0.36
        let normalizedEyeWidth = averageEyeWidth / max(faceBounds.width, 0.0001) / 0.12
        let normalizedEyeHeight = averageEyeHeight / max(faceBounds.height, 0.0001) / 0.05
        let normalizedMouthWidth = mouthBounds.width / max(faceBounds.width, 0.0001) / 0.28
        let normalizedMouthHeight = mouthBounds.height / max(faceBounds.height, 0.0001) / 0.08
        let normalizedNoseWidth = noseBounds.width / max(faceBounds.width, 0.0001) / 0.18
        func anonymized(_ value: Float, push: Float, min minValue: Float, max maxValue: Float) -> Float {
            let shifted = value >= 1 ? value + push : value - push
            return clamp(shifted, min: minValue, max: maxValue)
        }
        return [
            "useLiveTexture": 0,
            "derivedIdentity": 1,
            "faceWidthScale": anonymized(mirrored(normalizedEyeSpacing, baseShift: 0.12, min: 0.86, max: 1.16), push: 0.10, min: 0.76, max: 1.24) * faceWidthOverride,
            "jawWidthScale": anonymized(mirrored(normalizedMouthWidth, baseShift: 0.10, min: 0.82, max: 1.18), push: 0.10, min: 0.76, max: 1.28) * jawWidthOverride,
            "eyeSpacingScale": anonymized(mirrored(normalizedEyeSpacing, baseShift: 0.16, min: 0.84, max: 1.20), push: 0.12, min: 0.78, max: 1.30) * eyeSpacingOverride,
            "noseWidthScale": anonymized(mirrored(normalizedNoseWidth, baseShift: 0.12, min: 0.80, max: 1.18), push: 0.08, min: 0.70, max: 1.24) * noseWidthOverride,
            "mouthWidthScale": anonymized(mirrored(normalizedMouthWidth, baseShift: 0.10, min: 0.82, max: 1.16), push: 0.10, min: 0.76, max: 1.26) * mouthWidthOverride,
            "eyeScale": anonymized(mirrored(normalizedEyeWidth, baseShift: 0.08, min: 0.86, max: 1.20), push: 0.08, min: 0.80, max: 1.24),
            "eyeHeightScale": anonymized(mirrored(normalizedEyeHeight, baseShift: 0.10, min: 0.80, max: 1.24), push: 0.10, min: 0.74, max: 1.30),
            "mouthScale": anonymized(mirrored(normalizedMouthWidth, baseShift: 0.12, min: 0.82, max: 1.18), push: 0.12, min: 0.74, max: 1.28) * mouthWidthOverride,
            "mouthHeightScale": anonymized(mirrored(normalizedMouthHeight, baseShift: 0.14, min: 0.82, max: 1.30), push: 0.14, min: 0.74, max: 1.38),
            "headScaleY": 1.14,
            "cheekLift": 0.032,
            "jawDropBias": 0.022,
            "jawDepthScale": 1.22
        ]
    }

    func verticesLinked(toLandmarks landmarkIndices: Set<Int>, vertexMap: [Int]) -> [Int] {
        guard !landmarkIndices.isEmpty else { return [] }
        return vertexMap.enumerated().compactMap { idx, landmarkIndex in
            landmarkIndices.contains(landmarkIndex) ? idx : nil
        }
    }

    func expandedVertexRegion(_ indices: [Int], in mesh: AvatarMesh, radius: CGFloat) -> [Int] {
        guard !indices.isEmpty else { return [] }
        var set = Set(indices)
        for idx in indices where mesh.vertices.indices.contains(idx) {
            let origin = mesh.vertices[idx].position
            for candidate in mesh.vertices.indices where !set.contains(candidate) {
                if distance(mesh.vertices[candidate].position, origin) <= radius {
                    set.insert(candidate)
                }
            }
        }
        return Array(set)
    }

    func buildRig(current: FaceLandmarks, neutral: FaceLandmarks, confidence: Float) -> ExpressionRigFrame {
        let profile = calibrationProfile
        let neutralJaw = profile?.jawNeutral ?? neutral.jawOpen
        let neutralMouthOpen = profile?.mouthOpenNeutral ?? neutral.mouthOpen
        let neutralMouthWidth = profile?.mouthWidthNeutral ?? neutral.mouthWidth
        let neutralLipPucker = profile?.lipPuckerNeutral ?? neutral.lipPucker
        let neutralLeftBlink = profile?.leftEyeBlinkNeutral ?? neutral.leftEyeBlink
        let neutralRightBlink = profile?.rightEyeBlinkNeutral ?? neutral.rightEyeBlink

        let jawRange = profile?.jawRange ?? 0.18
        let mouthOpenRange = profile?.mouthOpenRange ?? 0.14
        let mouthWidthRange = profile?.mouthWidthRange ?? 0.10
        let lipPuckerRange = profile?.lipPuckerRange ?? 0.10
        let leftBlinkRange = profile?.leftEyeBlinkRange ?? 0.12
        let rightBlinkRange = profile?.rightEyeBlinkRange ?? 0.12

        let jawOpenDelta = clamp(((current.jawOpen - neutralJaw) / jawRange) * mouthSensitivity, min: -0.2, max: 1.8)
        let mouthWidthDelta = clamp(((current.mouthWidth - neutralMouthWidth) / mouthWidthRange) * mouthSensitivity * 0.5, min: -0.9, max: 0.9)
        let lipPuckerDelta = clamp(((current.lipPucker - neutralLipPucker) / lipPuckerRange) * mouthSensitivity * 0.6, min: -0.7, max: 1.2)
        let mouthOpenDelta = clamp(((current.mouthOpen - neutralMouthOpen) / mouthOpenRange) * mouthSensitivity, min: -0.2, max: 1.8)
        let absoluteJawOpen = clamp((current.jawOpen - neutralJaw + jawRange * 0.15) / jawRange * mouthSensitivity * 1.4, min: 0, max: 1.8)
        let leftBlink = clamp(max(
            (neutral.leftEyeOpen - current.leftEyeOpen) * eyeSensitivity * 2.1,
            ((current.leftEyeBlink - neutralLeftBlink) / leftBlinkRange) * eyeSensitivity * 1.3
        ), min: 0, max: 1.7)
        let rightBlink = clamp(max(
            (neutral.rightEyeOpen - current.rightEyeOpen) * eyeSensitivity * 2.1,
            ((current.rightEyeBlink - neutralRightBlink) / rightBlinkRange) * eyeSensitivity * 1.3
        ), min: 0, max: 1.7)
        let absoluteLeftBlink = clamp(current.leftEyeBlink * eyeSensitivity * 1.45, min: 0, max: 1.55)
        let absoluteRightBlink = clamp(current.rightEyeBlink * eyeSensitivity * 1.45, min: 0, max: 1.55)
        let leftBrow = clamp((current.leftBrowRaise - neutral.leftBrowRaise), min: -0.8, max: 0.8)
        let rightBrow = clamp((current.rightBrowRaise - neutral.rightBrowRaise), min: -0.8, max: 0.8)

        return ExpressionRigFrame(
            jawOpen: max(max(jawOpenDelta, mouthOpenDelta), absoluteJawOpen) * confidence,
            mouthOpen: mouthOpenDelta * confidence,
            mouthWidth: mouthWidthDelta * confidence,
            lipPucker: lipPuckerDelta * confidence,
            leftEyeBlink: max(leftBlink, absoluteLeftBlink) * confidence,
            rightEyeBlink: max(rightBlink, absoluteRightBlink) * confidence,
            leftBrowRaise: leftBrow,
            rightBrowRaise: rightBrow,
            gazeX: clamp(current.gazeX * 2.8, min: -1.0, max: 1.0) * confidence,
            gazeY: clamp(current.gazeY * 2.4, min: -1.0, max: 1.0) * confidence,
            headYaw: current.headEulerAngles.y - neutral.headEulerAngles.y,
            headPitch: current.headEulerAngles.x - neutral.headEulerAngles.x,
            headRoll: current.headEulerAngles.z - neutral.headEulerAngles.z,
            confidence: confidence
        )
    }

    func buildRegionLandmarkIndices(
        referenceLandmarks: [CGPoint],
        regionPoints: [AvatarRegion: [CGPoint]]
    ) -> [AvatarRegion: [Int]] {
        var result: [AvatarRegion: [Int]] = [:]
        for region in AvatarRegion.allCases {
            let points = regionPoints[region] ?? []
            guard !points.isEmpty, !referenceLandmarks.isEmpty else {
                result[region] = []
                continue
            }
            var indices = Set<Int>()
            for point in points {
                if let nearest = referenceLandmarks.enumerated().min(by: { lhs, rhs in
                    distance(lhs.element, point) < distance(rhs.element, point)
                }) {
                    indices.insert(nearest.offset)
                }
            }
            result[region] = Array(indices)
        }
        return result
    }

    func applyRegionDrivenDeformation(
        to mesh: inout AvatarMesh,
        vertexIndices: [Int],
        referenceLandmarks: [CGPoint],
        liveLandmarks: [CGPoint],
        landmarkIndices: [Int],
        strength: CGFloat,
        clampScaleX: (CGFloat, CGFloat),
        clampScaleY: (CGFloat, CGFloat)
    ) {
        guard !vertexIndices.isEmpty, !landmarkIndices.isEmpty else { return }
        let valid = landmarkIndices.filter { referenceLandmarks.indices.contains($0) && liveLandmarks.indices.contains($0) }
        guard valid.count >= 3 else { return }
        let refPoints = valid.map { referenceLandmarks[$0] }
        let livePoints = valid.map { liveLandmarks[$0] }

        let refCenter = centroid(of: refPoints)
        let liveCenter = centroid(of: livePoints)

        let refBBox = boundingBox(of: refPoints)
        let liveBBox = boundingBox(of: livePoints)

        let scaleXRaw = liveBBox.width / max(0.0001, refBBox.width)
        let scaleYRaw = liveBBox.height / max(0.0001, refBBox.height)
        let scaleX = min(max(scaleXRaw, clampScaleX.0), clampScaleX.1)
        let scaleY = min(max(scaleYRaw, clampScaleY.0), clampScaleY.1)
        let tx = (liveCenter.x - refCenter.x) * strength
        let ty = (liveCenter.y - refCenter.y) * strength

        for index in vertexIndices {
            guard mesh.vertices.indices.contains(index) else { continue }
            let p = mesh.vertices[index].position
            let dx = p.x - refCenter.x
            let dy = p.y - refCenter.y
            let transformed = CGPoint(
                x: refCenter.x + dx * scaleX + tx,
                y: refCenter.y + dy * scaleY + ty
            )
            // Blend parcial para estabilidad.
            mesh.vertices[index].position = CGPoint(
                x: clampUnit(p.x + (transformed.x - p.x) * strength),
                y: clampUnit(p.y + (transformed.y - p.y) * strength)
            )
        }
    }

    func boundingBox(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var minY = first.y
        var maxX = first.x
        var maxY = first.y
        for p in points {
            minX = min(minX, p.x)
            minY = min(minY, p.y)
            maxX = max(maxX, p.x)
            maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: max(0.0001, maxX - minX), height: max(0.0001, maxY - minY))
    }

    func buildVertexLandmarkMap(vertices: [AvatarVertex], landmarks: [CGPoint]) -> [Int] {
        guard !landmarks.isEmpty else {
            return Array(repeating: 0, count: vertices.count)
        }
        return vertices.map { vertex in
            var bestIndex = 0
            var bestDistance = CGFloat.greatestFiniteMagnitude
            for (index, landmark) in landmarks.enumerated() {
                let d = distance(vertex.position, landmark)
                if d < bestDistance {
                    bestDistance = d
                    bestIndex = index
                }
            }
            return bestIndex
        }
    }

    func applyLandmarkMotion(
        to mesh: inout AvatarMesh,
        referenceLandmarks: [CGPoint],
        liveLandmarks: [CGPoint],
        vertexMap: [Int],
        confidence: Float
    ) {
        guard !referenceLandmarks.isEmpty, !liveLandmarks.isEmpty, !vertexMap.isEmpty else { return }
        // Reduce al minimo la deformacion global para evitar "imagen estirada".
        let gain = CGFloat(0.05) * CGFloat(confidence)
        let maxDelta = CGFloat(0.03)
        let count = min(mesh.vertices.count, vertexMap.count)
        for i in 0..<count {
            let landmarkIndex = vertexMap[i]
            guard
                referenceLandmarks.indices.contains(landmarkIndex),
                liveLandmarks.indices.contains(landmarkIndex)
            else { continue }
            let ref = referenceLandmarks[landmarkIndex]
            let live = liveLandmarks[landmarkIndex]
            var delta = CGPoint(x: live.x - ref.x, y: live.y - ref.y)
            delta.x = min(max(delta.x, -maxDelta), maxDelta)
            delta.y = min(max(delta.y, -maxDelta), maxDelta)
            let base = mesh.vertices[i].position
            mesh.vertices[i].position = CGPoint(
                x: clampUnit(base.x + delta.x * gain),
                y: clampUnit(base.y + delta.y * gain)
            )
        }
    }

    func applyIdentityMorph(to mesh: inout AvatarMesh, avatarModel: AvatarModel) {
        let metadata = avatarModel.identityMetadata
        guard (metadata["derivedIdentity"] ?? 0) > 0.5 else { return }
        let center = centroid(of: mesh.vertices.map(\.position))
        let faceWidthScale = CGFloat(metadata["faceWidthScale"] ?? 1)
        let headScaleY = CGFloat(metadata["headScaleY"] ?? 1)
        let cheekLift = CGFloat(metadata["cheekLift"] ?? 0)
        for index in mesh.vertices.indices {
            var p = mesh.vertices[index].position
            let dx = p.x - center.x
            let dy = p.y - center.y
            p.x = clampUnit(center.x + dx * faceWidthScale)
            p.y = clampUnit(center.y + dy * headScaleY + cheekLift * max(0, 1 - abs(dx) * 2))
            mesh.vertices[index].position = p
        }
        scaleRegion(.jawline, avatarModel: avatarModel, mesh: &mesh, scaleX: CGFloat(metadata["jawWidthScale"] ?? 1), scaleY: 1.03, offset: CGPoint(x: 0, y: CGFloat(metadata["jawDropBias"] ?? 0)))
        scaleRegion(.leftEye, avatarModel: avatarModel, mesh: &mesh, scaleX: CGFloat(metadata["eyeScale"] ?? 1), scaleY: CGFloat(metadata["eyeHeightScale"] ?? 1), offset: .zero)
        scaleRegion(.rightEye, avatarModel: avatarModel, mesh: &mesh, scaleX: CGFloat(metadata["eyeScale"] ?? 1), scaleY: CGFloat(metadata["eyeHeightScale"] ?? 1), offset: .zero)
        translateEyes(avatarModel: avatarModel, mesh: &mesh, spacingScale: CGFloat(metadata["eyeSpacingScale"] ?? 1))
        scaleRegion(.nose, avatarModel: avatarModel, mesh: &mesh, scaleX: CGFloat(metadata["noseWidthScale"] ?? 1), scaleY: 1.05, offset: .zero)
        scaleRegion(
            .mouth,
            avatarModel: avatarModel,
            mesh: &mesh,
            scaleX: CGFloat(metadata["mouthScale"] ?? metadata["mouthWidthScale"] ?? 1),
            scaleY: CGFloat(metadata["mouthHeightScale"] ?? 0.94),
            offset: CGPoint(x: 0, y: -0.01)
        )
    }

    func scaleRegion(_ region: AvatarRegion, avatarModel: AvatarModel, mesh: inout AvatarMesh, scaleX: CGFloat, scaleY: CGFloat, offset: CGPoint) {
        let indices = avatarModel.segmentedRegionVertexIndices[region] ?? []
        guard !indices.isEmpty else { return }
        let regionCenter = centroid(of: indices.compactMap { mesh.vertices.indices.contains($0) ? mesh.vertices[$0].position : nil })
        for index in indices where mesh.vertices.indices.contains(index) {
            let p = mesh.vertices[index].position
            mesh.vertices[index].position = CGPoint(
                x: clampUnit(regionCenter.x + (p.x - regionCenter.x) * scaleX + offset.x),
                y: clampUnit(regionCenter.y + (p.y - regionCenter.y) * scaleY + offset.y)
            )
        }
    }

    func translateEyes(avatarModel: AvatarModel, mesh: inout AvatarMesh, spacingScale: CGFloat) {
        let leftIndices = avatarModel.segmentedRegionVertexIndices[.leftEye] ?? []
        let rightIndices = avatarModel.segmentedRegionVertexIndices[.rightEye] ?? []
        guard !leftIndices.isEmpty, !rightIndices.isEmpty else { return }
        let leftCenter = centroid(of: leftIndices.compactMap { mesh.vertices.indices.contains($0) ? mesh.vertices[$0].position : nil })
        let rightCenter = centroid(of: rightIndices.compactMap { mesh.vertices.indices.contains($0) ? mesh.vertices[$0].position : nil })
        let midX = (leftCenter.x + rightCenter.x) * 0.5
        let leftShift = (leftCenter.x - midX) * (spacingScale - 1)
        let rightShift = (rightCenter.x - midX) * (spacingScale - 1)
        for index in leftIndices where mesh.vertices.indices.contains(index) {
            mesh.vertices[index].position.x = clampUnit(mesh.vertices[index].position.x + leftShift)
        }
        for index in rightIndices where mesh.vertices.indices.contains(index) {
            mesh.vertices[index].position.x = clampUnit(mesh.vertices[index].position.x + rightShift)
        }
    }

    func segmentVertices(mesh: AvatarMesh, regionPoints: [AvatarRegion: [CGPoint]]) -> [AvatarRegion: [Int]] {
        var result: [AvatarRegion: [Int]] = [:]
        for region in AvatarRegion.allCases {
            let points = regionPoints[region] ?? []
            guard !points.isEmpty else {
                result[region] = []
                continue
            }

            var regionIndices = Set<Int>()
            let influenceRadius = regionInfluenceRadius(region)

            // Mapea cada landmark de la region a su vertice mas cercano.
            for regionPoint in points {
                if let closest = mesh.vertices.enumerated().min(by: { lhs, rhs in
                    distance(lhs.element.position, regionPoint) < distance(rhs.element.position, regionPoint)
                }) {
                    regionIndices.insert(closest.offset)
                    let centerPos = closest.element.position
                    // Incluye vecinos locales de esa region (no de toda la cara) para deformacion anatomica.
                    for (candidateIndex, candidateVertex) in mesh.vertices.enumerated() {
                        if distance(candidateVertex.position, centerPos) <= influenceRadius {
                            regionIndices.insert(candidateIndex)
                        }
                    }
                }
            }

            // Garantiza minimo de vertices por region.
            if regionIndices.count < 8 {
                let centroid = centroid(of: points)
                let sortedByCentroid = mesh.vertices.enumerated().sorted { lhs, rhs in
                    distance(lhs.element.position, centroid) < distance(rhs.element.position, centroid)
                }
                for entry in sortedByCentroid where regionIndices.count < 8 {
                    regionIndices.insert(entry.offset)
                }
            }
            result[region] = Array(regionIndices)
        }
        return result
    }

    func regionInfluenceRadius(_ region: AvatarRegion) -> CGFloat {
        switch region {
        case .mouth:
            return 0.065
        case .leftEye, .rightEye:
            return 0.05
        case .leftBrow, .rightBrow:
            return 0.055
        case .nose:
            return 0.06
        case .jawline:
            return 0.08
        }
    }

    func applyMouth(to mesh: inout AvatarMesh, indices: [Int], jawOpen: Float, mouthWidth: Float, lipPucker: Float) {
        guard !indices.isEmpty else { return }
        let regionPoints = indices.compactMap { mesh.vertices.indices.contains($0) ? mesh.vertices[$0].position : nil }
        let center = centroid(of: regionPoints)
        let jawPivot = CGPoint(x: center.x, y: center.y - 0.03)
        let jawAngle = CGFloat(jawOpen) * 0.34
        let openAmount = CGFloat(jawOpen) * 0.24
        let widthAmount = CGFloat(mouthWidth) * 0.024
        let puckerAmount = CGFloat(lipPucker) * 0.03
        for index in indices {
            guard mesh.vertices.indices.contains(index) else { continue }
            let p = mesh.vertices[index].position
            let radial = max(0.15, 1 - distance(p, center) * 4.5)
            let verticalDirection: CGFloat = (p.y >= center.y) ? 1 : -1
            // Mandibula real: labio inferior rota/cae mas que el superior.
            let lowerLipWeight = verticalDirection < 0 ? 1.0 : 0.32
            let y = p.y + openAmount * radial * verticalDirection * lowerLipWeight
            // Horizontal muy contenido para evitar artefacto de estiramiento.
            let x = p.x + widthAmount * radial * (p.x >= center.x ? 1 : -1)
            let rotated = rotate(point: CGPoint(x: x, y: y), around: jawPivot, angle: jawAngle * lowerLipWeight)
            // Pucker retrae hacia el centro.
            let px = rotated.x + (center.x - rotated.x) * puckerAmount * radial
            let py = rotated.y + (center.y - rotated.y) * puckerAmount * radial * 0.3
            mesh.vertices[index].position.y = clampUnit(py)
            mesh.vertices[index].position.x = clampUnit(px)
        }
    }

    func applyEyeBlink(to mesh: inout AvatarMesh, indices: [Int], blink: Float) {
        guard !indices.isEmpty else { return }
        let center = centroid(of: indices.compactMap { mesh.vertices.indices.contains($0) ? mesh.vertices[$0].position : nil })
        let amount = CGFloat(blink) * 1.15
        for index in indices {
            guard mesh.vertices.indices.contains(index) else { continue }
            let p = mesh.vertices[index].position
            let y = mesh.vertices[index].position.y
            mesh.vertices[index].position.y = clampUnit(y + (center.y - y) * amount)
            // Micro compresion horizontal al parpadear para evitar look plastico.
            mesh.vertices[index].position.x = clampUnit(p.x + (center.x - p.x) * amount * 0.15)
        }
    }

    func applyEyeGaze(to mesh: inout AvatarMesh, indices: [Int], gazeX: Float, gazeY: Float) {
        guard !indices.isEmpty else { return }
        let center = centroid(of: indices.compactMap { mesh.vertices.indices.contains($0) ? mesh.vertices[$0].position : nil })
        let amountX = CGFloat(gazeX) * 0.026
        let amountY = CGFloat(gazeY) * 0.020
        for index in indices {
            guard mesh.vertices.indices.contains(index) else { continue }
            let p = mesh.vertices[index].position
            let radial = max(0.2, 1 - distance(p, center) * 7)
            mesh.vertices[index].position.x = clampUnit(p.x + amountX * radial)
            mesh.vertices[index].position.y = clampUnit(p.y + amountY * radial)
        }
    }

    func applyBrow(to mesh: inout AvatarMesh, indices: [Int], delta: Float) {
        guard !indices.isEmpty else { return }
        let amount = CGFloat(delta) * 0.06
        for index in indices {
            guard mesh.vertices.indices.contains(index) else { continue }
            mesh.vertices[index].position.y = clampUnit(mesh.vertices[index].position.y + amount)
        }
    }

    func applyHeadTransform(to mesh: inout AvatarMesh, roll: Float, yaw: Float, pitch: Float) {
        let center = centroid(of: mesh.vertices.map(\.position))
        let cosA = CGFloat(cos(roll))
        let sinA = CGFloat(sin(roll))
        let tx = CGFloat(yaw) * 0.015
        let ty = CGFloat(pitch) * 0.015

        for i in mesh.vertices.indices {
            let p = mesh.vertices[i].position
            let dx = p.x - center.x
            let dy = p.y - center.y
            let rx = dx * cosA - dy * sinA
            let ry = dx * sinA + dy * cosA
            mesh.vertices[i].position = CGPoint(
                x: clampUnit(center.x + rx + tx),
                y: clampUnit(center.y + ry + ty)
            )
        }
    }

    func smooth(current: AvatarMesh, previous: AvatarMesh, factor: Float) -> AvatarMesh {
        guard current.vertices.count == previous.vertices.count else { return current }
        var output = current
        let alpha = CGFloat(1 - factor)
        for index in output.vertices.indices {
            let c = current.vertices[index].position
            let p = previous.vertices[index].position
            output.vertices[index].position = CGPoint(
                x: p.x + (c.x - p.x) * alpha,
                y: p.y + (c.y - p.y) * alpha
            )
        }
        return output
    }

    func centroid(of points: [CGPoint]) -> CGPoint {
        guard !points.isEmpty else { return CGPoint(x: 0.5, y: 0.5) }
        let x = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let y = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        return CGPoint(x: x, y: y)
    }

    func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    func clampUnit(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }

    func clamp(_ value: Float, min minValue: Float, max maxValue: Float) -> Float {
        Swift.min(Swift.max(value, minValue), maxValue)
    }

    func rotate(point: CGPoint, around pivot: CGPoint, angle: CGFloat) -> CGPoint {
        let c = cos(angle)
        let s = sin(angle)
        let dx = point.x - pivot.x
        let dy = point.y - pivot.y
        return CGPoint(
            x: pivot.x + dx * c - dy * s,
            y: pivot.y + dx * s + dy * c
        )
    }

    func buildCanonicalRig(from mesh: AvatarMesh, segmentedIndices: [AvatarRegion: [Int]], fitResult: CanonicalAvatarFitResult?) -> CanonicalBlendshapeRig {
        let mouth = segmentedIndices[.mouth] ?? []
        let leftEye = segmentedIndices[.leftEye] ?? []
        let rightEye = segmentedIndices[.rightEye] ?? []
        let leftBrow = segmentedIndices[.leftBrow] ?? []
        let rightBrow = segmentedIndices[.rightBrow] ?? []

        let mouthScale = CGFloat((fitResult?.identityMetadata["mouthScale"] ?? 1))
        let eyeScale = CGFloat((fitResult?.identityMetadata["eyeScale"] ?? 1))
        let browScale = CGFloat((fitResult?.identityMetadata["browScale"] ?? 1))

        let rigMap: [String: [CanonicalBlendshapeRig.Influence]] = [
            "jawOpen": [CanonicalBlendshapeRig.Influence(vertexIndices: mouth, delta: CGPoint(x: 0, y: -0.075 * mouthScale))],
            "mouthPucker": [CanonicalBlendshapeRig.Influence(vertexIndices: mouth, delta: CGPoint(x: 0, y: 0.018 * mouthScale))],
            "mouthFunnel": [CanonicalBlendshapeRig.Influence(vertexIndices: mouth, delta: CGPoint(x: 0, y: 0.012 * mouthScale))],
            "mouthSmileLeft": [CanonicalBlendshapeRig.Influence(vertexIndices: leftHalf(of: mouth, in: mesh), delta: CGPoint(x: -0.016 * mouthScale, y: 0.014 * mouthScale))],
            "mouthSmileRight": [CanonicalBlendshapeRig.Influence(vertexIndices: rightHalf(of: mouth, in: mesh), delta: CGPoint(x: 0.016 * mouthScale, y: 0.014 * mouthScale))],
            "mouthFrownLeft": [CanonicalBlendshapeRig.Influence(vertexIndices: leftHalf(of: mouth, in: mesh), delta: CGPoint(x: -0.011 * mouthScale, y: -0.013 * mouthScale))],
            "mouthFrownRight": [CanonicalBlendshapeRig.Influence(vertexIndices: rightHalf(of: mouth, in: mesh), delta: CGPoint(x: 0.011 * mouthScale, y: -0.013 * mouthScale))],
            "eyeBlinkLeft": [CanonicalBlendshapeRig.Influence(vertexIndices: leftEye, delta: CGPoint(x: 0, y: -0.042 * eyeScale))],
            "eyeBlinkRight": [CanonicalBlendshapeRig.Influence(vertexIndices: rightEye, delta: CGPoint(x: 0, y: -0.042 * eyeScale))],
            "browOuterUpLeft": [CanonicalBlendshapeRig.Influence(vertexIndices: leftBrow, delta: CGPoint(x: 0, y: 0.027 * browScale))],
            "browOuterUpRight": [CanonicalBlendshapeRig.Influence(vertexIndices: rightBrow, delta: CGPoint(x: 0, y: 0.027 * browScale))],
            "eyeLookOutLeft": [CanonicalBlendshapeRig.Influence(vertexIndices: leftEye, delta: CGPoint(x: 0.006 * eyeScale, y: 0))],
            "eyeLookOutRight": [CanonicalBlendshapeRig.Influence(vertexIndices: rightEye, delta: CGPoint(x: -0.006 * eyeScale, y: 0))],
            "eyeLookInLeft": [CanonicalBlendshapeRig.Influence(vertexIndices: leftEye, delta: CGPoint(x: -0.006 * eyeScale, y: 0))],
            "eyeLookInRight": [CanonicalBlendshapeRig.Influence(vertexIndices: rightEye, delta: CGPoint(x: 0.006 * eyeScale, y: 0))],
            "eyeLookUpLeft": [CanonicalBlendshapeRig.Influence(vertexIndices: leftEye, delta: CGPoint(x: 0, y: 0.005 * eyeScale))],
            "eyeLookUpRight": [CanonicalBlendshapeRig.Influence(vertexIndices: rightEye, delta: CGPoint(x: 0, y: 0.005 * eyeScale))],
            "eyeLookDownLeft": [CanonicalBlendshapeRig.Influence(vertexIndices: leftEye, delta: CGPoint(x: 0, y: -0.005 * eyeScale))],
            "eyeLookDownRight": [CanonicalBlendshapeRig.Influence(vertexIndices: rightEye, delta: CGPoint(x: 0, y: -0.005 * eyeScale))]
        ]
        return CanonicalBlendshapeRig(influences: rigMap)
    }

    func leftHalf(of indices: [Int], in mesh: AvatarMesh) -> [Int] {
        guard !indices.isEmpty else { return [] }
        let centerX = indices
            .compactMap { mesh.vertices.indices.contains($0) ? mesh.vertices[$0].position.x : nil }
            .reduce(0, +) / CGFloat(indices.count)
        return indices.filter { mesh.vertices.indices.contains($0) && mesh.vertices[$0].position.x < centerX }
    }

    func rightHalf(of indices: [Int], in mesh: AvatarMesh) -> [Int] {
        guard !indices.isEmpty else { return [] }
        let centerX = indices
            .compactMap { mesh.vertices.indices.contains($0) ? mesh.vertices[$0].position.x : nil }
            .reduce(0, +) / CGFloat(indices.count)
        return indices.filter { mesh.vertices.indices.contains($0) && mesh.vertices[$0].position.x >= centerX }
    }
}
