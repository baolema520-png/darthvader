import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import simd

final class AvatarMeshWarpRenderer {
    private var cachedTextureURL: URL?
    private var cachedTextureCGImage: CGImage?

    func renderAvatar(
        sourceImage: CIImage,
        extent: CGRect,
        avatarModel: AvatarModel,
        animatedMesh: AvatarMesh,
        landmarks: FaceLandmarks,
        ciContext: CIContext
    ) -> CIImage {
        guard let composited = drawMeshOverlay(
            sourceImage: sourceImage,
            extent: extent,
            avatarModel: avatarModel,
            mesh: animatedMesh,
            landmarks: landmarks,
            ciContext: ciContext
        ) else {
            return sourceImage
        }
        return composited
    }
}

private extension AvatarMeshWarpRenderer {
    func avatarTexture(for url: URL) -> CGImage? {
        if cachedTextureURL == url, let cachedTextureCGImage {
            return cachedTextureCGImage
        }
        guard
            let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
            let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            return nil
        }
        cachedTextureURL = url
        cachedTextureCGImage = cgImage
        return cgImage
    }

    func drawMeshOverlay(
        sourceImage: CIImage,
        extent: CGRect,
        avatarModel: AvatarModel,
        mesh: AvatarMesh,
        landmarks: FaceLandmarks,
        ciContext: CIContext
    ) -> CIImage? {
        guard
            let sourceCG = ciContext.createCGImage(sourceImage, from: extent)
        else {
            return nil
        }
        let colorSpace = sourceCG.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

        let width = Int(extent.width)
        let height = Int(extent.height)
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        else { return nil }

        // Render only avatar layer (transparent background). The final composition
        // with the real frame is handled by RenderingEngine using a controlled mask.
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))

        let faceRect = CGRect(
            x: landmarks.boundingBox.minX * extent.width,
            y: landmarks.boundingBox.minY * extent.height,
            width: landmarks.boundingBox.width * extent.width,
            height: landmarks.boundingBox.height * extent.height
        )
        let expandedFaceRect = CGRect(
            x: faceRect.minX - faceRect.width * 0.30,
            y: faceRect.minY - faceRect.height * 0.60,
            width: faceRect.width * 1.62,
            height: faceRect.height * 2.34
        ).intersection(extent).integral
        let usesLiveTexture = (avatarModel.identityMetadata["useLiveTexture"] ?? 0) > 0.5
        let texture: CGImage
        let flipVertically: Bool
        if usesLiveTexture, let liveCrop = sourceCG.cropping(to: expandedFaceRect) {
            texture = liveCrop
            flipVertically = false
        } else if let avatarTexture = avatarTexture(for: avatarModel.texturePath) {
            texture = avatarTexture
            flipVertically = true
        } else {
            return nil
        }

        drawTriangles(
            in: context,
            texture: texture,
            mesh: mesh,
            faceRect: expandedFaceRect,
            headEulerAngles: landmarks.headEulerAngles,
            flipVertically: flipVertically
        )
        guard let outputCG = context.makeImage() else { return nil }
        return CIImage(cgImage: outputCG)
    }

    func drawTriangles(
        in context: CGContext,
        texture: CGImage,
        mesh: AvatarMesh,
        faceRect: CGRect,
        headEulerAngles: simd_float3,
        flipVertically: Bool
    ) {
        guard mesh.indices.count.isMultiple(of: 3) else { return }
        let textureSize = CGSize(width: texture.width, height: texture.height)
        let center = CGPoint(x: faceRect.midX, y: faceRect.midY)

        for i in stride(from: 0, to: mesh.indices.count, by: 3) {
            let i0 = Int(mesh.indices[i])
            let i1 = Int(mesh.indices[i + 1])
            let i2 = Int(mesh.indices[i + 2])
            guard
                mesh.vertices.indices.contains(i0),
                mesh.vertices.indices.contains(i1),
                mesh.vertices.indices.contains(i2)
            else { continue }

            let v0 = mesh.vertices[i0]
            let v1 = mesh.vertices[i1]
            let v2 = mesh.vertices[i2]

            let dst0 = applyHeadPose(
                denormalize(v0.position, in: faceRect),
                center: center,
                headEulerAngles: headEulerAngles,
                faceRect: faceRect
            )
            let dst1 = applyHeadPose(
                denormalize(v1.position, in: faceRect),
                center: center,
                headEulerAngles: headEulerAngles,
                faceRect: faceRect
            )
            let dst2 = applyHeadPose(
                denormalize(v2.position, in: faceRect),
                center: center,
                headEulerAngles: headEulerAngles,
                faceRect: faceRect
            )

            let src0 = CGPoint(x: v0.uv.x * textureSize.width, y: (flipVertically ? (1 - v0.uv.y) : v0.uv.y) * textureSize.height)
            let src1 = CGPoint(x: v1.uv.x * textureSize.width, y: (flipVertically ? (1 - v1.uv.y) : v1.uv.y) * textureSize.height)
            let src2 = CGPoint(x: v2.uv.x * textureSize.width, y: (flipVertically ? (1 - v2.uv.y) : v2.uv.y) * textureSize.height)

            guard let transform = affineTransform(from: [src0, src1, src2], to: [dst0, dst1, dst2]) else {
                continue
            }

            context.saveGState()
            let path = CGMutablePath()
            path.move(to: dst0)
            path.addLine(to: dst1)
            path.addLine(to: dst2)
            path.closeSubpath()
            context.addPath(path)
            context.clip()
            context.concatenate(transform)
            context.draw(texture, in: CGRect(origin: .zero, size: textureSize))
            context.restoreGState()
        }
    }

    func denormalize(_ p: CGPoint, in rect: CGRect) -> CGPoint {
        CGPoint(
            x: rect.minX + p.x * rect.width,
            y: rect.minY + p.y * rect.height
        )
    }

    func applyHeadPose(_ point: CGPoint, center: CGPoint, headEulerAngles: simd_float3, faceRect: CGRect) -> CGPoint {
        let yaw = CGFloat(headEulerAngles.y)
        let pitch = CGFloat(headEulerAngles.x)
        let roll = CGFloat(headEulerAngles.z)

        let dx = point.x - center.x
        let dy = point.y - center.y
        let z = (1 - min(1, abs(dx) / max(1, faceRect.width * 0.5))) * faceRect.width * 0.08

        let rx = dx * cos(yaw) + z * sin(yaw)
        let rz = -dx * sin(yaw) + z * cos(yaw)
        let ry = dy * cos(pitch) - rz * sin(pitch)
        let rz2 = dy * sin(pitch) + rz * cos(pitch)
        let perspective = max(1, faceRect.width * 0.9)
        let scale = perspective / (perspective + rz2)
        let px = rx * scale
        let py = ry * scale
        let fx = px * cos(roll) - py * sin(roll)
        let fy = px * sin(roll) + py * cos(roll)
        return CGPoint(x: center.x + fx, y: center.y + fy)
    }

    func affineTransform(from src: [CGPoint], to dst: [CGPoint]) -> CGAffineTransform? {
        guard src.count == 3, dst.count == 3 else { return nil }

        var matrix: [[Double]] = []
        for i in 0..<3 {
            let x = Double(src[i].x)
            let y = Double(src[i].y)
            let X = Double(dst[i].x)
            let Y = Double(dst[i].y)

            matrix.append([x, y, 0, 0, 1, 0, X])
            matrix.append([0, 0, x, y, 0, 1, Y])
        }

        guard let solved = solveLinearSystem(matrix) else { return nil }
        return CGAffineTransform(
            a: solved[0],
            b: solved[2],
            c: solved[1],
            d: solved[3],
            tx: solved[4],
            ty: solved[5]
        )
    }

    func solveLinearSystem(_ input: [[Double]]) -> [CGFloat]? {
        var matrix = input
        let rows = matrix.count
        let cols = matrix[0].count

        for pivot in 0..<min(rows, cols - 1) {
            var maxRow = pivot
            var maxValue = abs(matrix[pivot][pivot])
            for r in (pivot + 1)..<rows {
                let value = abs(matrix[r][pivot])
                if value > maxValue {
                    maxValue = value
                    maxRow = r
                }
            }

            if maxValue < 1e-12 { return nil }
            if maxRow != pivot {
                matrix.swapAt(maxRow, pivot)
            }

            let pivotValue = matrix[pivot][pivot]
            for c in pivot..<cols {
                matrix[pivot][c] /= pivotValue
            }

            for r in 0..<rows where r != pivot {
                let factor = matrix[r][pivot]
                for c in pivot..<cols {
                    matrix[r][c] -= factor * matrix[pivot][c]
                }
            }
        }

        return (0..<6).map { CGFloat(matrix[$0][6]) }
    }
}
