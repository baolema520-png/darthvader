import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import Vision

struct AvatarPreprocessResult: Sendable, Equatable {
    var texturePath: URL
    var normalizedLandmarks: [CGPoint]
    var faceBoundingBox: CGRect
    var regionPoints: [AvatarRegion: [CGPoint]]
    var featureAnchors: AvatarFeatureAnchors
}

enum AvatarPreprocessorError: Error {
    case cannotLoadImage
    case noFaceDetected
    case cannotCreateProcessedTexture
}

final class AvatarPreprocessor {
    private let handler = VNSequenceRequestHandler()
    private let textureSize = CGSize(width: 1024, height: 1024)

    func preprocess(imageURL: URL) throws -> AvatarPreprocessResult {
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw AvatarPreprocessorError.cannotLoadImage
        }

        let request = VNDetectFaceLandmarksRequest()
        try handler.perform([request], on: cgImage)

        guard let observation = request.results?.max(by: { $0.boundingBox.area < $1.boundingBox.area }) else {
            throw AvatarPreprocessorError.noFaceDetected
        }

        let points = Self.flattenedPoints(from: observation.landmarks)
        guard !points.isEmpty else {
            throw AvatarPreprocessorError.noFaceDetected
        }
        let regions = Self.regionPoints(from: observation.landmarks)
        let anchors = Self.featureAnchors(from: regions)
        let processedTextureURL = try makeProcessedTexture(from: cgImage, faceObservation: observation, sourceURL: imageURL)
        return AvatarPreprocessResult(
            texturePath: processedTextureURL,
            normalizedLandmarks: points,
            faceBoundingBox: observation.boundingBox,
            regionPoints: regions,
            featureAnchors: anchors
        )
    }

    private func makeProcessedTexture(
        from image: CGImage,
        faceObservation: VNFaceObservation,
        sourceURL: URL
    ) throws -> URL {
        let imageRect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let faceRect = faceObservation.boundingBox.denormalized(in: imageRect)
        // Expande en sesgo superior para incluir frente/cabello y evitar recorte a media cara.
        let expanded = CGRect(
            x: faceRect.minX - faceRect.width * 0.35,
            y: faceRect.minY - faceRect.height * 0.78,
            width: faceRect.width * 1.70,
            height: faceRect.height * 2.35
        ).intersection(imageRect).integral
        guard
            expanded.width > 0,
            expanded.height > 0,
            let cropped = image.cropping(to: expanded)
        else {
            throw AvatarPreprocessorError.cannotCreateProcessedTexture
        }

        guard
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil,
                width: Int(textureSize.width),
                height: Int(textureSize.height),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else {
            throw AvatarPreprocessorError.cannotCreateProcessedTexture
        }

            // Keep background transparent so the renderer does not project
            // a black plate over the entire head region.
            context.setFillColor(NSColor.black.withAlphaComponent(0).cgColor)
        context.fill(CGRect(origin: .zero, size: textureSize))

        let drawRect = CGRect(origin: .zero, size: textureSize).aspectFillRect(for: CGSize(width: cropped.width, height: cropped.height))
        context.saveGState()
        // Normaliza el eje Y para que la textura final no quede invertida.
        context.translateBy(x: 0, y: textureSize.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(cropped, in: drawRect)
        context.restoreGState()

        guard let outputImage = context.makeImage() else {
            throw AvatarPreprocessorError.cannotCreateProcessedTexture
        }
        return try persistProcessedTexture(outputImage, sourceURL: sourceURL)
    }

    private func persistProcessedTexture(_ image: CGImage, sourceURL: URL) throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let outputDir = appSupport.appendingPathComponent("VirtualFaceCam/Avatars", isDirectory: true)
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)

        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let uniqueSuffix = UUID().uuidString.lowercased()
        let outputURL = outputDir.appendingPathComponent("\(baseName)-processed-\(uniqueSuffix).png")
        guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw AvatarPreprocessorError.cannotCreateProcessedTexture
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AvatarPreprocessorError.cannotCreateProcessedTexture
        }
        return outputURL
    }

    private static func flattenedPoints(from landmarks: VNFaceLandmarks2D?) -> [CGPoint] {
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

    private static func regionPoints(from landmarks: VNFaceLandmarks2D?) -> [AvatarRegion: [CGPoint]] {
        guard let landmarks else { return [:] }
        return [
            .mouth: points(from: landmarks.outerLips) + points(from: landmarks.innerLips),
            .leftEye: points(from: landmarks.leftEye),
            .rightEye: points(from: landmarks.rightEye),
            .leftBrow: points(from: landmarks.leftEyebrow),
            .rightBrow: points(from: landmarks.rightEyebrow),
            .nose: points(from: landmarks.nose),
            .jawline: points(from: landmarks.faceContour)
        ]
    }

    private static func points(from region: VNFaceLandmarkRegion2D?) -> [CGPoint] {
        guard let region else { return [] }
        return (0..<region.pointCount).map { i in
            let p = region.normalizedPoints[i]
            return CGPoint(x: CGFloat(p.x), y: CGFloat(p.y))
        }
    }

    private static func featureAnchors(from regions: [AvatarRegion: [CGPoint]]) -> AvatarFeatureAnchors {
        let leftEye = regions[.leftEye] ?? []
        let rightEye = regions[.rightEye] ?? []
        let mouth = regions[.mouth] ?? []

        let leftCenter = centroid(of: leftEye) ?? AvatarFeatureAnchors.neutral.leftEyeCenter
        let rightCenter = centroid(of: rightEye) ?? AvatarFeatureAnchors.neutral.rightEyeCenter
        let mouthCenter = centroid(of: mouth) ?? AvatarFeatureAnchors.neutral.mouthCenter
        let mouthSize = mouthBounds(points: mouth) ?? AvatarFeatureAnchors.neutral.mouthSize

        return AvatarFeatureAnchors(
            leftEyeCenter: leftCenter,
            rightEyeCenter: rightCenter,
            mouthCenter: mouthCenter,
            mouthSize: mouthSize
        )
    }

    private static func centroid(of points: [CGPoint]) -> CGPoint? {
        guard !points.isEmpty else { return nil }
        let x = points.map(\.x).reduce(0, +) / CGFloat(points.count)
        let y = points.map(\.y).reduce(0, +) / CGFloat(points.count)
        return CGPoint(x: x, y: y)
    }

    private static func mouthBounds(points: [CGPoint]) -> CGSize? {
        guard !points.isEmpty else { return nil }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else {
            return nil
        }
        return CGSize(width: max(0.04, maxX - minX), height: max(0.03, maxY - minY))
    }
}

private extension CGRect {
    var area: CGFloat { width * height }

    func expanded(by factor: CGFloat) -> CGRect {
        let dx = width * factor * 0.5
        let dy = height * factor * 0.5
        return insetBy(dx: -dx, dy: -dy)
    }
}

private extension CGRect {
    func aspectFillRect(for sourceSize: CGSize) -> CGRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return self }
        let scale = max(width / sourceSize.width, height / sourceSize.height)
        let drawSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        return CGRect(
            x: midX - drawSize.width * 0.5,
            y: midY - drawSize.height * 0.5,
            width: drawSize.width,
            height: drawSize.height
        )
    }
}

private extension CGRect {
    func denormalized(in imageRect: CGRect) -> CGRect {
        CGRect(
            x: minX * imageRect.width,
            y: (1 - maxY) * imageRect.height,
            width: width * imageRect.width,
            height: height * imageRect.height
        )
    }
}
