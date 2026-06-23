import AVFoundation
import AppKit
import CoreImage
import Foundation
import Metal

final class RenderingEngine: RenderingProviding {
    private let device: MTLDevice?
    private let ciContext: CIContext
    private let metalAvatarRenderer: MetalAvatarRenderer?
    private let cpuAvatarRenderer = AvatarMeshWarpRenderer()
    private let headMatteGenerator = HeadMatteGenerator()
    private var lastAvatarLandmarks: FaceLandmarks?
    private var previousCompositeMask: CIImage?
    private var previousAvatarLayer: CIImage?
    private var cachedBackgroundImageURL: URL?
    private var cachedBackgroundImage: CIImage?
    private let useDeterministicAvatarOutput = false
    private let useMetalAvatarPath = true
    private let useHardAvatarReplacement = true

    init() {
        self.device = MTLCreateSystemDefaultDevice()
        if let device {
            self.metalAvatarRenderer = MetalAvatarRenderer(device: device)
        } else {
            self.metalAvatarRenderer = nil
        }
        if let device {
            self.ciContext = CIContext(mtlDevice: device)
        } else {
            self.ciContext = CIContext()
        }
    }

    func render(
        sourceFrame: CVPixelBuffer,
        trackingMode: TrackingMode,
        blurIntensity: Float,
        pixelationIntensity: Float,
        backgroundMode: VirtualBackgroundMode,
        backgroundBlurIntensity: Float,
        backgroundColor: CIColor,
        backgroundImageURL: URL?,
        avatarModel: AvatarModel?,
        animatedMesh: AvatarMesh?,
        landmarks: [FaceLandmarks]
    ) -> CVPixelBuffer? {
        let sourceImage = CIImage(cvPixelBuffer: sourceFrame)
        let extent = sourceImage.extent
        let anonymizedImage: CIImage

        switch trackingMode {
        case .blur:
            anonymizedImage = applyBlur(
                to: sourceImage,
                landmarks: landmarks,
                extent: extent,
                radius: max(2, CGFloat(blurIntensity))
            )
        case .pixelate:
            anonymizedImage = applyPixelate(
                to: sourceImage,
                landmarks: landmarks,
                extent: extent,
                scale: max(4, CGFloat(pixelationIntensity))
            )
        }

        let composited = applyVirtualBackground(
            to: anonymizedImage,
            sourceImage: sourceImage,
            sourceFrame: sourceFrame,
            extent: extent,
            mode: backgroundMode,
            blurRadius: max(6, CGFloat(backgroundBlurIntensity)),
            color: backgroundColor,
            imageURL: backgroundImageURL
        )
        return renderToPixelBuffer(composited, size: extent.size)
    }
}

private extension RenderingEngine {
    func applyVirtualBackground(
        to foreground: CIImage,
        sourceImage: CIImage,
        sourceFrame: CVPixelBuffer,
        extent: CGRect,
        mode: VirtualBackgroundMode,
        blurRadius: CGFloat,
        color: CIColor,
        imageURL: URL?
    ) -> CIImage {
        guard mode != .none else { return foreground }
        guard let personMask = headMatteGenerator.fullBodyMaskImage(sourceFrame: sourceFrame, extent: extent) else {
            return foreground
        }

        let backgroundLayer: CIImage
        switch mode {
        case .none:
            return foreground
        case .blur:
            backgroundLayer = sourceImage
                .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": blurRadius])
                .cropped(to: extent)
        case .solidColor:
            backgroundLayer = CIImage(color: color).cropped(to: extent)
        case .image:
            backgroundLayer = backgroundImageLayer(for: imageURL, extent: extent) ?? sourceImage
                .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": blurRadius])
                .cropped(to: extent)
        }

        return foreground.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: backgroundLayer,
                kCIInputMaskImageKey: personMask
            ]
        ).cropped(to: extent)
    }

    func backgroundImageLayer(for imageURL: URL?, extent: CGRect) -> CIImage? {
        guard let imageURL else { return nil }
        if cachedBackgroundImageURL != imageURL {
            cachedBackgroundImageURL = imageURL
            cachedBackgroundImage = loadBackgroundImage(from: imageURL)
        }
        guard let image = cachedBackgroundImage else { return nil }

        let scale = max(
            extent.width / max(image.extent.width, 1),
            extent.height / max(image.extent.height, 1)
        )
        var transformed = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let translateX = extent.midX - transformed.extent.midX
        let translateY = extent.midY - transformed.extent.midY
        transformed = transformed.transformed(by: CGAffineTransform(translationX: translateX, y: translateY))
        return transformed.cropped(to: extent)
    }

    func loadBackgroundImage(from imageURL: URL) -> CIImage? {
        if let image = CIImage(contentsOf: imageURL, options: [.applyOrientationProperty: true]) {
            return image
        }
        guard
            let nsImage = NSImage(contentsOf: imageURL),
            let data = nsImage.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: data),
            let cgImage = bitmap.cgImage
        else {
            return nil
        }
        return CIImage(cgImage: cgImage)
    }

    func finalizeAvatarOutput(
        renderedPixelBuffer: CVPixelBuffer,
        sourceFrame: CVPixelBuffer,
        landmarks: FaceLandmarks,
        extent: CGRect
    ) -> CVPixelBuffer? {
        let renderedImage = CIImage(cvPixelBuffer: renderedPixelBuffer)
        let sourceImage = CIImage(cvPixelBuffer: sourceFrame)
        let refined = blendAvatarNaturally(
            rendered: renderedImage,
            source: sourceImage,
            sourceFrame: sourceFrame,
            landmarks: landmarks,
            extent: extent
        )
        let featureEnhanced = applyProceduralFeatureLayers(to: refined, landmarks: landmarks, extent: extent)
        return renderToPixelBuffer(featureEnhanced, size: extent.size)
    }

    func blendAvatarNaturally(
        rendered: CIImage,
        source: CIImage,
        sourceFrame: CVPixelBuffer,
        landmarks: FaceLandmarks,
        extent: CGRect
    ) -> CIImage {
        let faceRect = CGRect(
            x: landmarks.boundingBox.minX * extent.width,
            y: landmarks.boundingBox.minY * extent.height,
            width: landmarks.boundingBox.width * extent.width,
            height: landmarks.boundingBox.height * extent.height
        )
        let headRect = CGRect(
            x: faceRect.minX - faceRect.width * 0.32,
            y: faceRect.minY - faceRect.height * 0.62,
            width: faceRect.width * 1.68,
            height: faceRect.height * 2.40
        ).intersection(extent)
        guard headRect.width > 1, headRect.height > 1 else { return rendered }

        let geometricMask = makeHeadMaskImage(landmarks: landmarks, headRect: headRect, extent: extent)
        let semanticMask = headMatteGenerator.maskImage(
            sourceFrame: sourceFrame,
            faceBoundingBox: landmarks.boundingBox,
            extent: extent
        )
        let mask = makeProfessionalCompositeMask(
            primary: geometricMask,
            secondary: semanticMask,
            headRect: headRect,
            confidence: landmarks.expressionConfidence,
            extent: extent
        )
        let stabilizedMask = stabilizeMask(mask, confidence: landmarks.expressionConfidence, extent: extent)
        if useHardAvatarReplacement {
            let avatarLayer = rendered
                .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 0.4])
                .cropped(to: extent)
            let stabilizedAvatar = stabilizeAvatarLayer(avatarLayer, confidence: landmarks.expressionConfidence, extent: extent)
            let strengthenedMask = strengthenedReplacementMask(
                from: stabilizedMask,
                faceRect: faceRect,
                headRect: headRect,
                extent: extent
            )
            let opaqueAvatar = stabilizedAvatar.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1.35)
                ]
            ).cropped(to: extent)
            let relit = applyRelighting(rendered: opaqueAvatar, source: source, headRect: headRect)
            return relit.applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: source,
                    kCIInputMaskImageKey: strengthenedMask
                ]
            ).cropped(to: extent)
        } else {
            let matched = colorMatch(rendered: rendered, source: source, headRect: headRect)
            let relit = applyRelighting(rendered: matched, source: source, headRect: headRect)
            return relit.applyingFilter(
                "CIBlendWithMask",
                parameters: [
                    kCIInputBackgroundImageKey: source,
                    kCIInputMaskImageKey: stabilizedMask
                ]
            )
        }
    }

    func applyRelighting(rendered: CIImage, source: CIImage, headRect: CGRect) -> CIImage {
        guard let renderedAvg = averageColor(for: rendered, in: headRect), let sourceAvg = averageColor(for: source, in: headRect) else {
            return rendered
        }
        let renderedLuma = max(0.001, 0.2126 * renderedAvg.red + 0.7152 * renderedAvg.green + 0.0722 * renderedAvg.blue)
        let sourceLuma = max(0.001, 0.2126 * sourceAvg.red + 0.7152 * sourceAvg.green + 0.0722 * sourceAvg.blue)
        let warmShift = max(-0.08, min(0.08, Float(sourceAvg.red - renderedAvg.red) * 0.7))
        let coolShift = max(-0.08, min(0.08, Float(sourceAvg.blue - renderedAvg.blue) * 0.7))
        let globallyRelit = rendered.applyingFilter(
            "CIColorMatrix",
            parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: CGFloat(warmShift), y: 0, z: CGFloat(coolShift), w: 0)
            ]
        )
        let headMask = CIImage(color: .white)
            .cropped(to: headRect.insetBy(dx: -headRect.width * 0.08, dy: -headRect.height * 0.08))
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 22.0])
            .cropped(to: rendered.extent)
        let local = globallyRelit.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: 1.05,
                kCIInputBrightnessKey: CGFloat(sourceLuma - renderedLuma) * 0.14,
                kCIInputContrastKey: 1.04
            ]
        )
        return local.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: globallyRelit,
                kCIInputMaskImageKey: headMask
            ]
        )
    }

    func applyFeatureOcclusions(composited: CIImage, source: CIImage, landmarks: FaceLandmarks, extent: CGRect) -> CIImage {
        let mouthMask = makeFeatureMask(
            points: landmarks.mouthOuterPoints,
            extent: extent,
            expandX: 1.12,
            expandY: 1.20,
            blur: 7
        )
        let leftEyeMask = makeFeatureMask(
            points: landmarks.leftEyePoints,
            extent: extent,
            expandX: 1.25,
            expandY: 1.35,
            blur: 6
        )
        let rightEyeMask = makeFeatureMask(
            points: landmarks.rightEyePoints,
            extent: extent,
            expandX: 1.25,
            expandY: 1.35,
            blur: 6
        )

        let eyeUnion = leftEyeMask.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: rightEyeMask])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .cropped(to: extent)
        let totalMask = mouthMask.applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: eyeUnion])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .cropped(to: extent)

        // Preserve mouth/eyelid texture from source for natural occlusion details.
        return source.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: composited,
                kCIInputMaskImageKey: totalMask
            ]
        )
    }

    func makeFeatureMask(points: [CGPoint], extent: CGRect, expandX: CGFloat, expandY: CGFloat, blur: CGFloat) -> CIImage {
        guard points.count >= 4 else { return CIImage(color: .black).cropped(to: extent) }
        let projected = points.map { CGPoint(x: $0.x * extent.width, y: $0.y * extent.height) }
        let bbox = boundingBox(for: projected)
        guard bbox.width > 1, bbox.height > 1 else { return CIImage(color: .black).cropped(to: extent) }
        let expanded = CGRect(
            x: bbox.midX - bbox.width * expandX * 0.5,
            y: bbox.midY - bbox.height * expandY * 0.5,
            width: bbox.width * expandX,
            height: bbox.height * expandY
        ).intersection(extent)
        let base = CIImage(color: .white).cropped(to: expanded)
        return base
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": blur])
            .cropped(to: extent)
    }

    func boundingBox(for points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var minX = first.x
        var maxX = first.x
        var minY = first.y
        var maxY = first.y
        for point in points {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
        }
        return CGRect(x: minX, y: minY, width: max(1, maxX - minX), height: max(1, maxY - minY))
    }

    func combineMasks(primary: CIImage, secondary: CIImage?, extent: CGRect) -> CIImage {
        guard let secondary else { return primary }
        let union = primary.applyingFilter(
            "CIAdditionCompositing",
            parameters: [kCIInputBackgroundImageKey: secondary]
        )
        return union
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .cropped(to: extent)
    }

    func makeProfessionalCompositeMask(
        primary: CIImage,
        secondary: CIImage?,
        headRect: CGRect,
        confidence: Float,
        extent: CGRect
    ) -> CIImage {
        let union = combineMasks(primary: primary, secondary: secondary, extent: extent)
        let coreMask = CIImage(color: .white)
            .cropped(to: headRect.insetBy(dx: headRect.width * 0.16, dy: headRect.height * 0.12))
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 10.0])
            .cropped(to: extent)
        let hardCoreMask = CIImage(color: .white)
            .cropped(to: headRect.insetBy(dx: headRect.width * 0.25, dy: headRect.height * 0.20))
            .cropped(to: extent)
        let reinforced = union
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: coreMask])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: hardCoreMask])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .cropped(to: extent)
        let radius = adaptiveFeatherRadius(headRect: headRect, confidence: confidence)
        return reinforced
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": radius])
            .cropped(to: extent)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.0,
                kCIInputBrightnessKey: 0.02,
                kCIInputContrastKey: 1.28
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .cropped(to: extent)
    }

    func adaptiveFeatherRadius(headRect: CGRect, confidence: Float) -> CGFloat {
        let base = max(14, min(headRect.width, headRect.height) * 0.08)
        let lowConfidenceBoost = CGFloat(max(0, 1 - confidence)) * 9
        return base + lowConfidenceBoost
    }

    func strengthenedReplacementMask(from mask: CIImage, faceRect: CGRect, headRect: CGRect, extent: CGRect) -> CIImage {
        let faceCore = CIImage(color: .white)
            .cropped(to: CGRect(
                x: faceRect.minX - faceRect.width * 0.12,
                y: faceRect.minY - faceRect.height * 0.18,
                width: faceRect.width * 1.24,
                height: faceRect.height * 1.46
            ).intersection(extent))
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 8.0])
            .cropped(to: extent)
        let headCore = CIImage(color: .white)
            .cropped(to: CGRect(
                x: headRect.minX - headRect.width * 0.06,
                y: headRect.minY - headRect.height * 0.04,
                width: headRect.width * 1.12,
                height: headRect.height * 1.08
            ).intersection(extent))
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 18.0])
            .cropped(to: extent)
        return mask
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: faceCore])
            .applyingFilter("CIAdditionCompositing", parameters: [kCIInputBackgroundImageKey: headCore])
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 1.0,
                kCIInputBrightnessKey: 0.05,
                kCIInputContrastKey: 1.34
            ])
            .applyingFilter("CIColorClamp", parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ])
            .cropped(to: extent)
    }

    func stabilizeMask(_ mask: CIImage, confidence: Float, extent: CGRect) -> CIImage {
        guard let previousMask = previousCompositeMask else {
            previousCompositeMask = mask
            return mask
        }
        // More inertia when confidence is low to avoid edge flicker.
        let alpha = CGFloat(min(max(0.84 + confidence * 0.12, 0.84), 0.97))
        let alphaMask = CIImage(color: CIColor(red: alpha, green: alpha, blue: alpha, alpha: 1)).cropped(to: extent)
        let blended = mask.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: previousMask,
                kCIInputMaskImageKey: alphaMask
            ]
        ).cropped(to: extent)
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 1.1])
            .cropped(to: extent)
        previousCompositeMask = blended
        return blended
    }

    func stabilizeAvatarLayer(_ avatar: CIImage, confidence: Float, extent: CGRect) -> CIImage {
        guard let previousLayer = previousAvatarLayer else {
            previousAvatarLayer = avatar
            return avatar
        }
        let alpha = CGFloat(min(max(0.86 + confidence * 0.10, 0.86), 0.98))
        let alphaMask = CIImage(color: CIColor(red: alpha, green: alpha, blue: alpha, alpha: 1)).cropped(to: extent)
        let blended = avatar.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: previousLayer,
                kCIInputMaskImageKey: alphaMask
            ]
        ).cropped(to: extent)
        previousAvatarLayer = blended
        return blended
    }

    func applyProceduralFeatureLayers(to image: CIImage, landmarks: FaceLandmarks, extent: CGRect) -> CIImage {
        var composed = image

        if let mouth = mouthFeatureRect(landmarks: landmarks, extent: extent) {
            let mouthOpen = max(landmarks.jawOpen, landmarks.mouthOpen)
            let cavity = CIImage(color: CIColor(red: 0.08, green: 0.02, blue: 0.02, alpha: 1))
                .cropped(to: CGRect(
                    x: mouth.midX - mouth.width * 0.42,
                    y: mouth.midY - mouth.height * (0.18 + CGFloat(mouthOpen) * 0.10),
                    width: mouth.width * 0.84,
                    height: max(2, mouth.height * CGFloat(0.16 + mouthOpen * 0.68))
                ))
                .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 2.8])
                .cropped(to: extent)
            composed = cavity.applyingFilter(
                "CISourceOverCompositing",
                parameters: [kCIInputBackgroundImageKey: composed]
            )

            // Teeth hint for natural mouth structure.
            if mouthOpen > 0.16 {
                let teeth = CIImage(color: CIColor(red: 0.94, green: 0.93, blue: 0.90, alpha: 0.88))
                    .cropped(to: CGRect(
                        x: mouth.midX - mouth.width * 0.34,
                        y: mouth.midY + mouth.height * 0.03,
                        width: mouth.width * 0.68,
                        height: max(1, mouth.height * 0.15)
                    ))
                    .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 1.2])
                    .cropped(to: extent)
                composed = teeth.applyingFilter(
                    "CISourceOverCompositing",
                    parameters: [kCIInputBackgroundImageKey: composed]
                )
            }
        }

        if let leftEye = eyeFeatureRect(points: landmarks.leftEyePoints, extent: extent) {
            composed = applyEyeOverlay(to: composed, eyeRect: leftEye, landmarks: landmarks, isLeft: true, extent: extent)
        }
        if let rightEye = eyeFeatureRect(points: landmarks.rightEyePoints, extent: extent) {
            composed = applyEyeOverlay(to: composed, eyeRect: rightEye, landmarks: landmarks, isLeft: false, extent: extent)
        }
        return composed
    }

    func applyEyeOverlay(to image: CIImage, eyeRect: CGRect, landmarks: FaceLandmarks, isLeft: Bool, extent: CGRect) -> CIImage {
        var out = image
        let blink = isLeft ? landmarks.leftEyeBlink : landmarks.rightEyeBlink
        let gx = CGFloat(landmarks.gazeX)
        let gy = CGFloat(landmarks.gazeY)
        let pupilCenter = CGPoint(
            x: eyeRect.midX + gx * eyeRect.width * 0.14,
            y: eyeRect.midY + gy * eyeRect.height * 0.10
        )
        let pupilRadius = max(1.5, min(eyeRect.width, eyeRect.height) * 0.16)
        let pupil = CIImage(color: CIColor(red: 0.04, green: 0.04, blue: 0.05, alpha: 0.96))
            .cropped(to: CGRect(
                x: pupilCenter.x - pupilRadius,
                y: pupilCenter.y - pupilRadius,
                width: pupilRadius * 2,
                height: pupilRadius * 2
            ))
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 0.9])
            .cropped(to: extent)
        out = pupil.applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: out])

        let lidHeight = eyeRect.height * CGFloat(min(max(blink * 0.9, 0.06), 0.95))
        let upperLid = CIImage(color: CIColor(red: 0.52, green: 0.40, blue: 0.38, alpha: 0.40))
            .cropped(to: CGRect(
                x: eyeRect.minX - eyeRect.width * 0.08,
                y: eyeRect.maxY - lidHeight,
                width: eyeRect.width * 1.16,
                height: lidHeight
            ))
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 1.8])
            .cropped(to: extent)
        return upperLid.applyingFilter("CISourceOverCompositing", parameters: [kCIInputBackgroundImageKey: out])
    }

    func eyeFeatureRect(points: [CGPoint], extent: CGRect) -> CGRect? {
        guard points.count >= 4 else { return nil }
        let projected = points.map { CGPoint(x: $0.x * extent.width, y: $0.y * extent.height) }
        let bbox = boundingBox(for: projected)
        guard bbox.width > 1, bbox.height > 1 else { return nil }
        return CGRect(
            x: bbox.midX - bbox.width * 0.62,
            y: bbox.midY - bbox.height * 0.70,
            width: bbox.width * 1.24,
            height: bbox.height * 1.40
        ).intersection(extent)
    }

    func mouthFeatureRect(landmarks: FaceLandmarks, extent: CGRect) -> CGRect? {
        guard landmarks.mouthOuterPoints.count >= 4 else { return nil }
        let projected = landmarks.mouthOuterPoints.map { CGPoint(x: $0.x * extent.width, y: $0.y * extent.height) }
        let bbox = boundingBox(for: projected)
        guard bbox.width > 1, bbox.height > 1 else { return nil }
        return CGRect(
            x: bbox.midX - bbox.width * 0.58,
            y: bbox.midY - bbox.height * 0.45,
            width: bbox.width * 1.16,
            height: bbox.height * 0.90
        ).intersection(extent)
    }

    func colorMatch(rendered: CIImage, source: CIImage, headRect: CGRect) -> CIImage {
        let renderedAvg = averageColor(for: rendered, in: headRect)
        let sourceAvg = averageColor(for: source, in: headRect)
        guard let renderedAvg, let sourceAvg else { return rendered }

        let renderedLuma = max(0.001, 0.2126 * renderedAvg.red + 0.7152 * renderedAvg.green + 0.0722 * renderedAvg.blue)
        let sourceLuma = max(0.001, 0.2126 * sourceAvg.red + 0.7152 * sourceAvg.green + 0.0722 * sourceAvg.blue)
        let brightnessDelta = (sourceLuma - renderedLuma) * 0.6
        let contrast = max(0.9, min(1.15, sourceLuma / renderedLuma))
        let sourceSat = max(sourceAvg.red, max(sourceAvg.green, sourceAvg.blue)) - min(sourceAvg.red, min(sourceAvg.green, sourceAvg.blue))
        let renderedSat = max(renderedAvg.red, max(renderedAvg.green, renderedAvg.blue)) - min(renderedAvg.red, min(renderedAvg.green, renderedAvg.blue))
        let saturation = max(0.88, min(1.15, renderedSat > 0.001 ? sourceSat / renderedSat : 1))

        return rendered.applyingFilter(
            "CIColorControls",
            parameters: [
                kCIInputSaturationKey: saturation,
                kCIInputBrightnessKey: brightnessDelta,
                kCIInputContrastKey: contrast
            ]
        )
    }

    func averageColor(for image: CIImage, in rect: CGRect) -> CIColor? {
        guard
            let filter = CIFilter(name: "CIAreaAverage"),
            !rect.isEmpty
        else { return nil }
        filter.setValue(image, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: rect), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        ciContext.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpace(name: CGColorSpace.sRGB)
        )
        return CIColor(
            red: CGFloat(pixel[0]) / 255.0,
            green: CGFloat(pixel[1]) / 255.0,
            blue: CGFloat(pixel[2]) / 255.0,
            alpha: CGFloat(pixel[3]) / 255.0
        )
    }

    func makeHeadMaskImage(landmarks: FaceLandmarks, headRect: CGRect, extent: CGRect) -> CIImage {
        let radial = radialMask(headRect: headRect, extent: extent)
        guard landmarks.faceContourPoints.count >= 8 else { return radial }
        let size = CGSize(width: extent.width, height: extent.height)
        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let ctx = CGContext(
                data: nil,
                width: Int(size.width),
                height: Int(size.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            return radial
        }
        ctx.setFillColor(NSColor.clear.cgColor)
        ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(NSColor.white.cgColor)

        let contour = landmarks.faceContourPoints.map { point in
            CGPoint(x: point.x * extent.width, y: point.y * extent.height)
        }
        let expanded = expandContour(contour, around: CGPoint(x: headRect.midX, y: headRect.midY), scaleX: 1.20, scaleY: 1.52)

        let path = CGMutablePath()
        if let first = expanded.first {
            path.move(to: first)
            for point in expanded.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
            ctx.addPath(path)
            ctx.fillPath()
        }

        guard let image = ctx.makeImage() else { return radial }
        let contourMask = CIImage(cgImage: image)
            .cropped(to: extent)
            .applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 20])
            .cropped(to: extent)
        // Union aditiva: evita que el contour opaque el radial y recorte frente/ojos.
        let union = contourMask.applyingFilter(
            "CIAdditionCompositing",
            parameters: [kCIInputBackgroundImageKey: radial]
        )
        return union.applyingFilter(
            "CIColorClamp",
            parameters: [
                "inputMinComponents": CIVector(x: 0, y: 0, z: 0, w: 0),
                "inputMaxComponents": CIVector(x: 1, y: 1, z: 1, w: 1)
            ]
        )
    }

    func expandContour(_ points: [CGPoint], around center: CGPoint, scaleX: CGFloat, scaleY: CGFloat) -> [CGPoint] {
        points.map { p in
            CGPoint(
                x: center.x + (p.x - center.x) * scaleX,
                y: center.y + (p.y - center.y) * scaleY
            )
        }
    }

    func radialMask(headRect: CGRect, extent: CGRect) -> CIImage {
        let center = CGPoint(x: headRect.midX, y: headRect.midY - headRect.height * 0.06)
        let radius = max(headRect.width, headRect.height) * 0.56
        let feather = max(18, radius * 0.30)
        return CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(cgPoint: center),
                "inputRadius0": radius,
                "inputRadius1": radius + feather,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black
            ]
        )?.outputImage?.cropped(to: extent) ?? CIImage(color: .black).cropped(to: extent)
    }

    func applyBlur(to source: CIImage, landmarks: [FaceLandmarks], extent: CGRect, radius: CGFloat) -> CIImage {
        guard !landmarks.isEmpty else { return source }
        let blurred = source.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": radius])
        let mask = combinedFaceMask(for: landmarks, extent: extent)
        return blurred.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: source,
                kCIInputMaskImageKey: mask
            ]
        )
    }

    func applyPixelate(to source: CIImage, landmarks: [FaceLandmarks], extent: CGRect, scale: CGFloat) -> CIImage {
        guard !landmarks.isEmpty else { return source }
        let pixelated = source.applyingFilter("CIPixellate", parameters: ["inputScale": scale])
        let mask = combinedFaceMask(for: landmarks, extent: extent)
        return pixelated.applyingFilter(
            "CIBlendWithMask",
            parameters: [
                kCIInputBackgroundImageKey: source,
                kCIInputMaskImageKey: mask
            ]
        )
    }

    func combinedFaceMask(for landmarks: [FaceLandmarks], extent: CGRect) -> CIImage {
        let masks = landmarks.map { softFaceMask(for: $0.boundingBox, extent: extent) }
        return masks.dropFirst().reduce(masks[0]) { partial, next in
            next.applyingFilter("CIMaximumCompositing", parameters: [
                kCIInputBackgroundImageKey: partial
            ])
        }
    }

    func softFaceMask(for normalizedFaceBBox: CGRect, extent: CGRect) -> CIImage {
        let faceRect = CGRect(
            x: normalizedFaceBBox.minX * extent.width,
            y: normalizedFaceBBox.minY * extent.height,
            width: normalizedFaceBBox.width * extent.width,
            height: normalizedFaceBBox.height * extent.height
        )
        let center = CGPoint(x: faceRect.midX, y: faceRect.midY + faceRect.height * 0.05)
        let radius = max(faceRect.width, faceRect.height) * 0.62
        let feather = max(12, radius * 0.25)

        let radial = CIFilter(
            name: "CIRadialGradient",
            parameters: [
                "inputCenter": CIVector(cgPoint: center),
                "inputRadius0": radius,
                "inputRadius1": radius + feather,
                "inputColor0": CIColor.white,
                "inputColor1": CIColor.black
            ]
        )?.outputImage?.cropped(to: extent)

        return radial ?? CIImage(color: .black).cropped(to: extent)
    }

    func renderToPixelBuffer(_ image: CIImage, size: CGSize) -> CVPixelBuffer? {
        var outputBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true,
            kCVPixelBufferMetalCompatibilityKey as String: true
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(size.width),
            Int(size.height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &outputBuffer
        )
        guard status == kCVReturnSuccess, let outputBuffer else { return nil }
        ciContext.render(image, to: outputBuffer)
        return outputBuffer
    }

    func hasSufficientAvatarCoverage(renderedPixelBuffer: CVPixelBuffer, extent: CGRect) -> Bool {
        let image = CIImage(cvPixelBuffer: renderedPixelBuffer)
        guard let avg = averageColor(for: image, in: extent) else { return false }
        // If Metal outputs only tiny artifacts (e.g. white strip), fallback to CPU renderer.
        return avg.alpha > 0.04
    }
}
