import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

final class ProceduralIdentityTextureGenerator {
    private let textureSize = CGSize(width: 1024, height: 1024)

    func generateTexture(
        featureAnchors: AvatarFeatureAnchors,
        identityMetadata: [String: Float],
        sourceLandmarks: FaceLandmarks,
        existingURL: URL? = nil
    ) throws -> URL {
        let outputURL = try existingURL ?? makeOutputURL()
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
            throw CocoaError(.fileWriteUnknown)
        }

        context.setFillColor(NSColor.clear.cgColor)
        context.fill(CGRect(origin: .zero, size: textureSize))

        let palette = makePalette(from: sourceLandmarks, metadata: identityMetadata)
        let canvas = CGRect(origin: .zero, size: textureSize)
        let headRect = CGRect(
            x: canvas.width * 0.18,
            y: canvas.height * 0.08,
            width: canvas.width * 0.64,
            height: canvas.height * 0.84
        )
        drawHead(in: context, rect: headRect, palette: palette, metadata: identityMetadata)
        drawBrows(in: context, rect: headRect, anchors: featureAnchors, palette: palette, metadata: identityMetadata)
        drawEyes(in: context, rect: headRect, anchors: featureAnchors, palette: palette, metadata: identityMetadata)
        drawNose(in: context, rect: headRect, anchors: featureAnchors, palette: palette, metadata: identityMetadata)
        drawMouth(in: context, rect: headRect, anchors: featureAnchors, palette: palette, metadata: identityMetadata)

        guard let image = context.makeImage() else {
            throw CocoaError(.fileWriteUnknown)
        }
        try persist(image: image, to: outputURL)
        return outputURL
    }
}

private extension ProceduralIdentityTextureGenerator {
    struct Palette {
        let skin: NSColor
        let shadow: NSColor
        let highlight: NSColor
        let lip: NSColor
        let iris: NSColor
        let brow: NSColor
        let nose: NSColor
    }

    func makeOutputURL() throws -> URL {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let outputDir = appSupport.appendingPathComponent("VirtualFaceCam/DerivedIdentity", isDirectory: true)
        try fm.createDirectory(at: outputDir, withIntermediateDirectories: true)
        return outputDir.appendingPathComponent("procedural-identity-\(UUID().uuidString.lowercased()).png")
    }

    func persist(image: CGImage, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw CocoaError(.fileWriteUnknown)
        }
    }

    func makePalette(from landmarks: FaceLandmarks, metadata: [String: Float]) -> Palette {
        let faceAspect = max(0.7, min(1.4, landmarks.boundingBox.height / max(landmarks.boundingBox.width, 0.0001)))
        let warmth = CGFloat(max(-0.08, min(0.08, (faceAspect - 1.0) * 0.08)))
        let jawBias = CGFloat((metadata["jawWidthScale"] ?? 1) - 1) * 0.12
        let base = NSColor(
            calibratedRed: 0.72 + warmth + jawBias * 0.15,
            green: 0.56 + warmth * 0.4,
            blue: 0.50 - warmth * 0.28,
            alpha: 1
        ).clamped
        return Palette(
            skin: base,
            shadow: base.blended(withFraction: 0.28, of: NSColor(calibratedWhite: 0.12, alpha: 1)) ?? .darkGray,
            highlight: base.blended(withFraction: 0.20, of: .white) ?? .lightGray,
            lip: NSColor(calibratedRed: 0.55, green: 0.25, blue: 0.29, alpha: 1),
            iris: NSColor(calibratedRed: 0.20, green: 0.28, blue: 0.24, alpha: 1),
            brow: NSColor(calibratedRed: 0.18, green: 0.12, blue: 0.10, alpha: 1),
            nose: base.blended(withFraction: 0.18, of: NSColor(calibratedRed: 0.68, green: 0.46, blue: 0.42, alpha: 1)) ?? base
        )
    }

    func drawHead(in context: CGContext, rect: CGRect, palette: Palette, metadata: [String: Float]) {
        context.saveGState()
        let faceWidthScale = CGFloat(metadata["faceWidthScale"] ?? 1)
        let headScaleY = CGFloat(metadata["headScaleY"] ?? 1)
        let headRect = CGRect(
            x: rect.midX - rect.width * 0.30 * faceWidthScale,
            y: rect.midY - rect.height * 0.42 * headScaleY,
            width: rect.width * 0.60 * faceWidthScale,
            height: rect.height * 0.84 * headScaleY
        )
        let path = CGPath(roundedRect: headRect, cornerWidth: headRect.width * 0.42, cornerHeight: headRect.width * 0.42, transform: nil)
        context.addPath(path)
        context.clip()
        let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: [palette.highlight.cgColor, palette.skin.cgColor, palette.shadow.cgColor] as CFArray,
            locations: [0.0, 0.52, 1.0]
        )!
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: headRect.midX, y: headRect.maxY),
            end: CGPoint(x: headRect.midX, y: headRect.minY),
            options: []
        )
        context.setFillColor(palette.shadow.withAlphaComponent(0.16).cgColor)
        context.fillEllipse(in: CGRect(
            x: headRect.midX - headRect.width * 0.36,
            y: headRect.minY + headRect.height * 0.18,
            width: headRect.width * 0.72,
            height: headRect.height * 0.64
        ))
        context.restoreGState()
    }

    func drawEyes(in context: CGContext, rect: CGRect, anchors: AvatarFeatureAnchors, palette: Palette, metadata: [String: Float]) {
        let eyeScale = CGFloat(metadata["eyeScale"] ?? 1)
        let eyeHeightScale = CGFloat(metadata["eyeHeightScale"] ?? 1)
        let eyeSpacingScale = CGFloat(metadata["eyeSpacingScale"] ?? 1)
        for anchor in [anchors.leftEyeCenter, anchors.rightEyeCenter] {
            let shiftedX = 0.5 + (anchor.x - 0.5) * eyeSpacingScale
            let center = CGPoint(
                x: rect.minX + shiftedX * rect.width,
                y: rect.minY + anchor.y * rect.height
            )
            let eyeRect = CGRect(
                x: center.x - rect.width * 0.075 * eyeScale,
                y: center.y - rect.height * 0.028 * eyeHeightScale,
                width: rect.width * 0.15 * eyeScale,
                height: rect.height * 0.056 * eyeHeightScale
            )
            context.setFillColor(NSColor.white.withAlphaComponent(0.96).cgColor)
            context.fillEllipse(in: eyeRect)
            let irisRect = eyeRect.insetBy(dx: eyeRect.width * 0.30, dy: eyeRect.height * 0.10)
            context.setFillColor(palette.iris.cgColor)
            context.fillEllipse(in: irisRect)
            let pupilRect = irisRect.insetBy(dx: irisRect.width * 0.28, dy: irisRect.height * 0.18)
            context.setFillColor(NSColor.black.withAlphaComponent(0.94).cgColor)
            context.fillEllipse(in: pupilRect)
            context.setStrokeColor(palette.brow.withAlphaComponent(0.82).cgColor)
            context.setLineWidth(rect.height * 0.012)
            context.strokeLineSegments(between: [
                CGPoint(x: eyeRect.minX, y: eyeRect.maxY + rect.height * 0.036),
                CGPoint(x: eyeRect.maxX, y: eyeRect.maxY + rect.height * 0.042)
            ])
        }
    }

    func drawBrows(in context: CGContext, rect: CGRect, anchors: AvatarFeatureAnchors, palette: Palette, metadata: [String: Float]) {
        let browLift = CGFloat(metadata["cheekLift"] ?? 0.02)
        for anchor in [anchors.leftEyeCenter, anchors.rightEyeCenter] {
            let center = CGPoint(
                x: rect.minX + anchor.x * rect.width,
                y: rect.minY + (anchor.y + 0.08 + browLift) * rect.height
            )
            let browRect = CGRect(
                x: center.x - rect.width * 0.08,
                y: center.y - rect.height * 0.010,
                width: rect.width * 0.16,
                height: rect.height * 0.02
            )
            context.setFillColor(palette.brow.withAlphaComponent(0.72).cgColor)
            context.fillEllipse(in: browRect)
        }
    }

    func drawNose(in context: CGContext, rect: CGRect, anchors: AvatarFeatureAnchors, palette: Palette, metadata: [String: Float]) {
        let noseWidth = CGFloat(metadata["noseWidthScale"] ?? 1)
        let center = CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.48)
        let noseRect = CGRect(
            x: center.x - rect.width * 0.06 * noseWidth,
            y: center.y - rect.height * 0.10,
            width: rect.width * 0.12 * noseWidth,
            height: rect.height * 0.20
        )
        context.setFillColor(palette.nose.withAlphaComponent(0.34).cgColor)
        context.fillEllipse(in: noseRect)
        context.setFillColor(palette.shadow.withAlphaComponent(0.20).cgColor)
        context.fillEllipse(in: CGRect(
            x: noseRect.midX - noseRect.width * 0.28,
            y: noseRect.minY + noseRect.height * 0.68,
            width: noseRect.width * 0.56,
            height: noseRect.height * 0.20
        ))
    }

    func drawMouth(in context: CGContext, rect: CGRect, anchors: AvatarFeatureAnchors, palette: Palette, metadata: [String: Float]) {
        let mouthScale = CGFloat(metadata["mouthScale"] ?? 1)
        let mouthHeightScale = CGFloat(metadata["mouthHeightScale"] ?? 1)
        let center = CGPoint(
            x: rect.minX + anchors.mouthCenter.x * rect.width,
            y: rect.minY + anchors.mouthCenter.y * rect.height
        )
        let mouthRect = CGRect(
            x: center.x - rect.width * 0.12 * mouthScale,
            y: center.y - rect.height * 0.03 * mouthHeightScale,
            width: rect.width * 0.24 * mouthScale,
            height: rect.height * 0.06 * mouthHeightScale
        )
        context.setFillColor(palette.lip.withAlphaComponent(0.86).cgColor)
        context.fillEllipse(in: mouthRect)
        context.setFillColor(NSColor.black.withAlphaComponent(0.28).cgColor)
        context.fillEllipse(in: mouthRect.insetBy(dx: mouthRect.width * 0.12, dy: mouthRect.height * 0.35))
        context.setFillColor(NSColor.white.withAlphaComponent(0.20).cgColor)
        context.fillEllipse(in: CGRect(
            x: mouthRect.minX + mouthRect.width * 0.14,
            y: mouthRect.midY,
            width: mouthRect.width * 0.72,
            height: mouthRect.height * 0.18
        ))
    }
}

private extension NSColor {
    var clamped: NSColor {
        let rgb = usingColorSpace(.sRGB) ?? self
        return NSColor(
            calibratedRed: min(max(rgb.redComponent, 0), 1),
            green: min(max(rgb.greenComponent, 0), 1),
            blue: min(max(rgb.blueComponent, 0), 1),
            alpha: min(max(rgb.alphaComponent, 0), 1)
        )
    }
}
