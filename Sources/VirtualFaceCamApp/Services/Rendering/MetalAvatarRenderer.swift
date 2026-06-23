import AVFoundation
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Metal
import MetalKit
import simd

final class MetalAvatarRenderer {
    private struct FullscreenVertex {
        var position: simd_float2
        var uv: simd_float2
    }

    private struct MeshVertex {
        var clipPosition: simd_float3
        var uv: simd_float2
        var alpha: Float
    }

    private struct FeatureUniforms {
        var tint: simd_float4
        var strength: Float
        var pad0: simd_float3 = .zero
    }

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private let copyPipelineState: MTLRenderPipelineState
    private let avatarPipelineState: MTLRenderPipelineState
    private let featurePipelineState: MTLRenderPipelineState
    private let solidFeaturePipelineState: MTLRenderPipelineState
    private let samplerState: MTLSamplerState
    private let textureLoader: MTKTextureLoader
    private var textureCache: CVMetalTextureCache?
    private var cachedAvatarTextureURL: URL?
    private var cachedAvatarTexture: MTLTexture?
    private var outputPool: CVPixelBufferPool?
    private var outputSize: CGSize = .zero
    private let canonicalDiscMesh = CanonicalHeadGeometry.makeDiscMesh(segments: 28)
    private let canonicalHeadMesh = CanonicalHeadGeometry.makeHeadMesh(columns: 36, rows: 28)

    init?(device: MTLDevice) {
        guard let commandQueue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = commandQueue
        self.textureLoader = MTKTextureLoader(device: device)

        var cache: CVMetalTextureCache?
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
        self.textureCache = cache

        guard
            let library = device.makeDefaultLibrary(),
            let copyVertex = library.makeFunction(name: "fullScreenCopyVertex"),
            let copyFragment = library.makeFunction(name: "copyFragment"),
            let meshVertex = library.makeFunction(name: "avatarMeshVertex"),
            let meshFragment = library.makeFunction(name: "avatarMeshFragment"),
            let featureFragment = library.makeFunction(name: "avatarFeatureFragment"),
            let solidFeatureFragment = library.makeFunction(name: "featureSolidFragment")
        else { return nil }

        do {
            let copyDescriptor = MTLRenderPipelineDescriptor()
            copyDescriptor.vertexFunction = copyVertex
            copyDescriptor.fragmentFunction = copyFragment
            copyDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            copyDescriptor.vertexDescriptor = Self.fullscreenVertexDescriptor
            self.copyPipelineState = try device.makeRenderPipelineState(descriptor: copyDescriptor)

            let avatarDescriptor = MTLRenderPipelineDescriptor()
            avatarDescriptor.vertexFunction = meshVertex
            avatarDescriptor.fragmentFunction = meshFragment
            avatarDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            avatarDescriptor.vertexDescriptor = Self.meshVertexDescriptor
            avatarDescriptor.colorAttachments[0].isBlendingEnabled = true
            avatarDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            avatarDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            avatarDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            avatarDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            self.avatarPipelineState = try device.makeRenderPipelineState(descriptor: avatarDescriptor)

            let featureDescriptor = MTLRenderPipelineDescriptor()
            featureDescriptor.vertexFunction = meshVertex
            featureDescriptor.fragmentFunction = featureFragment
            featureDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            featureDescriptor.vertexDescriptor = Self.meshVertexDescriptor
            featureDescriptor.colorAttachments[0].isBlendingEnabled = true
            featureDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            featureDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            featureDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            featureDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            self.featurePipelineState = try device.makeRenderPipelineState(descriptor: featureDescriptor)

            let solidDescriptor = MTLRenderPipelineDescriptor()
            solidDescriptor.vertexFunction = meshVertex
            solidDescriptor.fragmentFunction = solidFeatureFragment
            solidDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            solidDescriptor.vertexDescriptor = Self.meshVertexDescriptor
            solidDescriptor.colorAttachments[0].isBlendingEnabled = true
            solidDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            solidDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            solidDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            solidDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            self.solidFeaturePipelineState = try device.makeRenderPipelineState(descriptor: solidDescriptor)
        } catch {
            return nil
        }

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        guard let samplerState = device.makeSamplerState(descriptor: samplerDescriptor) else { return nil }
        self.samplerState = samplerState
    }

    func render(
        sourceFrame: CVPixelBuffer,
        avatarModel: AvatarModel,
        animatedMesh: AvatarMesh,
        landmarks: FaceLandmarks
    ) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(sourceFrame)
        let height = CVPixelBufferGetHeight(sourceFrame)
        let usesLiveTexture = (avatarModel.identityMetadata["useLiveTexture"] ?? 0) > 0.5

        guard
            let outputBuffer = makeOutputPixelBuffer(width: width, height: height),
            let outputTexture = makeTexture(from: outputBuffer, width: width, height: height)
        else { return nil }
        let sourceTexture = makeTexture(from: sourceFrame, width: width, height: height)
        let avatarTexture = usesLiveTexture ? sourceTexture : loadAvatarTexture(from: avatarModel.texturePath)
        guard let sampledTexture = avatarTexture else { return nil }

        let meshVertices: [MeshVertex]
        let headIndices: [UInt16]
        if usesLiveTexture {
            meshVertices = buildHeadMeshVertices(
                mesh: animatedMesh,
                faceBox: landmarks.boundingBox,
                headEulerAngles: landmarks.headEulerAngles,
                identityMetadata: avatarModel.identityMetadata,
                usesLiveTexture: true
            )
            headIndices = animatedMesh.indices
        } else {
            meshVertices = buildCanonicalHeadVertices(
                faceBox: landmarks.boundingBox,
                headEulerAngles: landmarks.headEulerAngles,
                identityMetadata: avatarModel.identityMetadata
            )
            headIndices = canonicalHeadMesh.indices
        }
        let eyeVertices = buildEyeLayerVertices(
            faceBox: landmarks.boundingBox,
            headEulerAngles: landmarks.headEulerAngles,
            anchors: avatarModel.featureAnchors,
            landmarks: landmarks,
            identityMetadata: avatarModel.identityMetadata
        )
        let mouthVertices = buildMouthLayerVertices(
            faceBox: landmarks.boundingBox,
            headEulerAngles: landmarks.headEulerAngles,
            anchors: avatarModel.featureAnchors,
            landmarks: landmarks,
            identityMetadata: avatarModel.identityMetadata
        )
        guard
            !meshVertices.isEmpty,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return sourceFrame }

        let renderPass = MTLRenderPassDescriptor()
        renderPass.colorAttachments[0].texture = outputTexture
        renderPass.colorAttachments[0].loadAction = .clear
        renderPass.colorAttachments[0].storeAction = .store
        // Avatar-only layer with transparent background.
        renderPass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)

        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPass) else {
            return sourceFrame
        }

        if
            let meshVertexBuffer = device.makeBuffer(
                bytes: meshVertices,
                length: MemoryLayout<MeshVertex>.stride * meshVertices.count
            ),
            let indexBuffer = device.makeBuffer(
                bytes: headIndices,
                length: MemoryLayout<UInt16>.stride * headIndices.count
            )
        {
            encoder.setRenderPipelineState(avatarPipelineState)
            encoder.setVertexBuffer(meshVertexBuffer, offset: 0, index: 0)
            encoder.setFragmentTexture(sampledTexture, index: 0)
            encoder.setFragmentSamplerState(samplerState, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: headIndices.count,
                indexType: .uint16,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0
            )
        }

        if
            !mouthVertices.isEmpty,
            let mouthVertexBuffer = device.makeBuffer(
                bytes: mouthVertices,
                length: MemoryLayout<MeshVertex>.stride * mouthVertices.count
            ),
            let mouthIndexBuffer = device.makeBuffer(
                bytes: repeatedDiscIndices(instanceCount: 1),
                length: MemoryLayout<UInt16>.stride * repeatedDiscIndices(instanceCount: 1).count
            )
        {
            var mouthUniform = FeatureUniforms(
                tint: simd_float4(0.10, 0.03, 0.03, 0.94),
                strength: min(max(landmarks.jawOpen * 0.95 + landmarks.mouthOpen * 0.45, 0.25), 1.0)
            )
            encoder.setRenderPipelineState(solidFeaturePipelineState)
            encoder.setVertexBuffer(mouthVertexBuffer, offset: 0, index: 0)
            encoder.setFragmentBytes(&mouthUniform, length: MemoryLayout<FeatureUniforms>.stride, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: repeatedDiscIndices(instanceCount: 1).count,
                indexType: .uint16,
                indexBuffer: mouthIndexBuffer,
                indexBufferOffset: 0
            )
        }

        if
            !eyeVertices.isEmpty,
            let eyeVertexBuffer = device.makeBuffer(
                bytes: eyeVertices,
                length: MemoryLayout<MeshVertex>.stride * eyeVertices.count
            ),
            let eyeIndexBuffer = device.makeBuffer(
                bytes: repeatedDiscIndices(instanceCount: 2),
                length: MemoryLayout<UInt16>.stride * repeatedDiscIndices(instanceCount: 2).count
            )
        {
            var eyeUniform = FeatureUniforms(
                tint: simd_float4(0.05, 0.05, 0.06, 0.92),
                strength: min(max(max(landmarks.leftEyeBlink, landmarks.rightEyeBlink) * 0.78 + 0.22, 0.2), 1.0)
            )
            encoder.setRenderPipelineState(solidFeaturePipelineState)
            encoder.setVertexBuffer(eyeVertexBuffer, offset: 0, index: 0)
            encoder.setFragmentBytes(&eyeUniform, length: MemoryLayout<FeatureUniforms>.stride, index: 0)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: repeatedDiscIndices(instanceCount: 2).count,
                indexType: .uint16,
                indexBuffer: eyeIndexBuffer,
                indexBufferOffset: 0
            )
        }

        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return outputBuffer
    }
}

private extension MetalAvatarRenderer {
    static var fullscreenVertexDescriptor: MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float2
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float2
        descriptor.attributes[1].offset = MemoryLayout<Float>.stride * 2
        descriptor.attributes[1].bufferIndex = 0
        descriptor.layouts[0].stride = MemoryLayout<FullscreenVertex>.stride
        descriptor.layouts[0].stepFunction = .perVertex
        return descriptor
    }

    static var meshVertexDescriptor: MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        descriptor.attributes[0].format = .float3
        descriptor.attributes[0].offset = 0
        descriptor.attributes[0].bufferIndex = 0
        descriptor.attributes[1].format = .float2
        descriptor.attributes[1].offset = MemoryLayout<Float>.stride * 3
        descriptor.attributes[1].bufferIndex = 0
        descriptor.attributes[2].format = .float
        descriptor.attributes[2].offset = MemoryLayout<Float>.stride * 5
        descriptor.attributes[2].bufferIndex = 0
        descriptor.layouts[0].stride = MemoryLayout<MeshVertex>.stride
        descriptor.layouts[0].stepFunction = .perVertex
        return descriptor
    }

    func makeTexture(from pixelBuffer: CVPixelBuffer, width: Int, height: Int) -> MTLTexture? {
        guard let textureCache else { return nil }
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTexture else { return nil }
        return CVMetalTextureGetTexture(cvTexture)
    }

    func makeOutputPixelBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        if outputPool == nil || outputSize != CGSize(width: width, height: height) {
            outputSize = CGSize(width: width, height: height)
            outputPool = createOutputPool(width: width, height: height)
        }
        guard let outputPool else { return nil }
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, outputPool, &pixelBuffer)
        guard status == kCVReturnSuccess else { return nil }
        return pixelBuffer
    }

    func createOutputPool(width: Int, height: Int) -> CVPixelBufferPool? {
        var pool: CVPixelBufferPool?
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferMetalCompatibilityKey: true,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary
        ]
        let poolAttributes: [CFString: Any] = [
            kCVPixelBufferPoolMinimumBufferCountKey: 3
        ]
        CVPixelBufferPoolCreate(
            kCFAllocatorDefault,
            poolAttributes as CFDictionary,
            attributes as CFDictionary,
            &pool
        )
        return pool
    }

    func loadAvatarTexture(from url: URL) -> MTLTexture? {
        if cachedAvatarTextureURL == url, let cachedAvatarTexture {
            return cachedAvatarTexture
        }

        guard let texture = try? textureLoader.newTexture(
            URL: url,
            options: [
                MTKTextureLoader.Option.SRGB: false,
                MTKTextureLoader.Option.origin: MTKTextureLoader.Origin.flippedVertically
            ]
        ) else {
            return nil
        }
        cachedAvatarTextureURL = url
        cachedAvatarTexture = texture
        return texture
    }

    private func buildHeadMeshVertices(
        mesh: AvatarMesh,
        faceBox: CGRect,
        headEulerAngles: simd_float3,
        identityMetadata: [String: Float],
        usesLiveTexture: Bool
    ) -> [MeshVertex] {
        let expandedFaceBox = expandedHeadBox(from: faceBox)
        let center = CGPoint(
            x: expandedFaceBox.midX,
            y: expandedFaceBox.midY - expandedFaceBox.height * 0.07
        )
        let radiusX = max(expandedFaceBox.width * 0.56, 0.0001)
        let headScaleY = CGFloat(identityMetadata["headScaleY"] ?? 1.0)
        let radiusY = max(expandedFaceBox.height * 0.78 * headScaleY, 0.0001)
        let yaw = CGFloat(headEulerAngles.y) * 1.12
        let pitch = CGFloat(headEulerAngles.x) * 1.02
        let roll = CGFloat(headEulerAngles.z) * 0.88
        let perspective = max(0.0001, expandedFaceBox.width * 0.90)

        var output: [MeshVertex] = []
        output.reserveCapacity(mesh.vertices.count)
        for vertex in mesh.vertices {
            let baseX = expandedFaceBox.minX + vertex.position.x * expandedFaceBox.width
            let baseY = expandedFaceBox.minY + vertex.position.y * expandedFaceBox.height
            let localX = baseX - center.x
            let localY = baseY - center.y
            let nx = localX / radiusX
            let ny = localY / radiusY
            let radial = max(0, 1 - nx * nx - ny * ny)
            let localZ = sqrt(radial) * expandedFaceBox.width * 0.14
            let projected = projectPoint(
                local: CGPoint3(x: localX, y: localY, z: localZ),
                center: center,
                yaw: yaw,
                pitch: pitch,
                roll: roll,
                perspective: perspective
            )
            let clip = simd_float3(
                Float(projected.x * 2 - 1),
                Float(projected.y * 2 - 1),
                Float(projected.z * 0.002)
            )
            let dx = projected.x - center.x
            let dy = projected.y - center.y
            let distX = (dx * dx) / (radiusX * radiusX)
            let distY = (dy * dy) / (radiusY * radiusY)
            let dist = sqrt(distX + distY)
            let alpha: Float
            if usesLiveTexture {
                alpha = Float(max(0.82, min(1, 1.06 - dist * 0.26)))
            } else {
                alpha = Float(max(0.38, min(1, 1.12 - dist * 0.55)))
            }
            let uv = mappedUV(
                original: vertex.uv,
                expandedFaceBox: expandedFaceBox,
                usesLiveTexture: usesLiveTexture
            )
            output.append(MeshVertex(
                clipPosition: clip,
                uv: uv,
                alpha: alpha
            ))
        }
        return output
    }

    private func buildCanonicalHeadVertices(
        faceBox: CGRect,
        headEulerAngles: simd_float3,
        identityMetadata: [String: Float]
    ) -> [MeshVertex] {
        let expandedFaceBox = expandedHeadBox(from: faceBox)
        let center = CGPoint(
            x: expandedFaceBox.midX,
            y: expandedFaceBox.midY - expandedFaceBox.height * 0.06
        )
        let yaw = CGFloat(headEulerAngles.y) * 1.12
        let pitch = CGFloat(headEulerAngles.x) * 1.02
        let roll = CGFloat(headEulerAngles.z) * 0.88
        let perspective = max(0.0001, expandedFaceBox.width * 0.92)
        let faceWidthScale = CGFloat(identityMetadata["faceWidthScale"] ?? 1.0)
        let headScaleY = CGFloat(identityMetadata["headScaleY"] ?? 1.0)
        return zip(canonicalHeadMesh.positions, canonicalHeadMesh.uvs).map { position, uv in
            let local = CGPoint3(
                x: CGFloat(position.x) * expandedFaceBox.width * 0.50 * faceWidthScale,
                y: CGFloat(position.y) * expandedFaceBox.height * 0.52 * headScaleY,
                z: CGFloat(position.z) * expandedFaceBox.width * 0.34
            )
            let projected = projectPoint(
                local: local,
                center: center,
                yaw: yaw,
                pitch: pitch,
                roll: roll,
                perspective: perspective
            )
            return MeshVertex(
                clipPosition: simd_float3(
                    Float(projected.x * 2 - 1),
                    Float(projected.y * 2 - 1),
                    Float(projected.z * 0.002)
                ),
                uv: uv,
                alpha: 0.98
            )
        }
    }

    private func mappedUV(
        original: CGPoint,
        expandedFaceBox: CGRect,
        usesLiveTexture: Bool
    ) -> simd_float2 {
        guard usesLiveTexture else {
            return simd_float2(Float(original.x), Float(original.y))
        }
        let u = min(max(expandedFaceBox.minX + original.x * expandedFaceBox.width, 0), 1)
        let v = min(max(expandedFaceBox.minY + original.y * expandedFaceBox.height, 0), 1)
        return simd_float2(Float(u), Float(v))
    }

    private func expandedHeadBox(from faceBox: CGRect) -> CGRect {
        var rect = CGRect(
            x: faceBox.minX - faceBox.width * 0.45,
            y: faceBox.minY - faceBox.height * 0.82,
            width: faceBox.width * 1.96,
            height: faceBox.height * 2.92
        )
        rect.origin.x = min(max(rect.origin.x, 0), 1)
        rect.origin.y = min(max(rect.origin.y, 0), 1)
        rect.size.width = min(rect.width, 1 - rect.origin.x)
        rect.size.height = min(rect.height, 1 - rect.origin.y)
        return rect
    }

    private func buildEyeLayerVertices(
        faceBox: CGRect,
        headEulerAngles: simd_float3,
        anchors: AvatarFeatureAnchors,
        landmarks: FaceLandmarks,
        identityMetadata: [String: Float]
    ) -> [MeshVertex] {
        let expandedFaceBox = expandedHeadBox(from: faceBox)
        let center = CGPoint(x: expandedFaceBox.midX, y: expandedFaceBox.midY - expandedFaceBox.height * 0.07)
        let yaw = CGFloat(headEulerAngles.y) * 1.10
        let pitch = CGFloat(headEulerAngles.x) * 1.00
        let roll = CGFloat(headEulerAngles.z) * 0.85
        let perspective = max(0.0001, expandedFaceBox.width * 0.75)
        let eyeScale = CGFloat(identityMetadata["eyeScale"] ?? 1.0)
        let eyeSpacingScale = CGFloat(identityMetadata["eyeSpacingScale"] ?? 1.0)
        let eyeHeightScale = CGFloat(identityMetadata["eyeHeightScale"] ?? 1.0)

        let left = buildEyeDiscVertices(
            eyeCenterUV: CGPoint(x: 0.5 + (anchors.leftEyeCenter.x - 0.5) * eyeSpacingScale, y: anchors.leftEyeCenter.y),
            eyeBlink: landmarks.leftEyeBlink,
            gazeX: landmarks.gazeX,
            gazeY: landmarks.gazeY,
            expandedFaceBox: expandedFaceBox,
            center: center,
            yaw: yaw,
            pitch: pitch,
            roll: roll,
            perspective: perspective,
            eyeScale: eyeScale,
            eyeHeightScale: eyeHeightScale
        )
        let right = buildEyeDiscVertices(
            eyeCenterUV: CGPoint(x: 0.5 + (anchors.rightEyeCenter.x - 0.5) * eyeSpacingScale, y: anchors.rightEyeCenter.y),
            eyeBlink: landmarks.rightEyeBlink,
            gazeX: landmarks.gazeX,
            gazeY: landmarks.gazeY,
            expandedFaceBox: expandedFaceBox,
            center: center,
            yaw: yaw,
            pitch: pitch,
            roll: roll,
            perspective: perspective,
            eyeScale: eyeScale,
            eyeHeightScale: eyeHeightScale
        )
        return left + right
    }

    private func buildEyeDiscVertices(
        eyeCenterUV: CGPoint,
        eyeBlink: Float,
        gazeX: Float,
        gazeY: Float,
        expandedFaceBox: CGRect,
        center: CGPoint,
        yaw: CGFloat,
        pitch: CGFloat,
        roll: CGFloat,
        perspective: CGFloat,
        eyeScale: CGFloat,
        eyeHeightScale: CGFloat
    ) -> [MeshVertex] {
        let cx = (eyeCenterUV.x - 0.5) * 1.00
        let cy = (eyeCenterUV.y - 0.5) * 1.25
        let blinkScale = max(0.18, 1 - CGFloat(eyeBlink) * 0.86)
        let gx = CGFloat(gazeX) * 0.035
        let gy = CGFloat(gazeY) * 0.028

        return zip(canonicalDiscMesh.positions, canonicalDiscMesh.uvs).map { position, uv in
            let px = CGFloat(position.x) * 0.08 * eyeScale + CGFloat(cx) + gx
            let py = CGFloat(position.y) * 0.045 * blinkScale * eyeHeightScale + CGFloat(cy) + gy
            let pz = CGFloat(position.z) + 0.105
            let local = CGPoint3(
                x: px * expandedFaceBox.width,
                y: py * expandedFaceBox.height,
                z: pz * expandedFaceBox.width
            )
            let projected = projectPoint(local: local, center: center, yaw: yaw, pitch: pitch, roll: roll, perspective: perspective)
            return MeshVertex(
                clipPosition: simd_float3(
                    Float(projected.x * 2 - 1),
                    Float(projected.y * 2 - 1),
                    Float(projected.z * 0.002)
                ),
                uv: simd_float2(uv.x, uv.y),
                alpha: 0.92
            )
        }
    }

    private func buildMouthLayerVertices(
        faceBox: CGRect,
        headEulerAngles: simd_float3,
        anchors: AvatarFeatureAnchors,
        landmarks: FaceLandmarks,
        identityMetadata: [String: Float]
    ) -> [MeshVertex] {
        let expandedFaceBox = expandedHeadBox(from: faceBox)
        let center = CGPoint(x: expandedFaceBox.midX, y: expandedFaceBox.midY - expandedFaceBox.height * 0.07)
        let yaw = CGFloat(headEulerAngles.y) * 1.10
        let pitch = CGFloat(headEulerAngles.x) * 1.00
        let roll = CGFloat(headEulerAngles.z) * 0.85
        let perspective = max(0.0001, expandedFaceBox.width * 0.75)
        let open = max(landmarks.jawOpen, landmarks.mouthOpen)
        let mouthScale = CGFloat(identityMetadata["mouthScale"] ?? 1.0)
        let mouthHeightScale = CGFloat(identityMetadata["mouthHeightScale"] ?? 1.0)
        let jawDepthScale = CGFloat(identityMetadata["jawDepthScale"] ?? 1.0)
        let mouthOffset = CGFloat(identityMetadata["mouthVerticalOffset"] ?? 0)

        let mouthCx = (anchors.mouthCenter.x - 0.5) * 1.02
        let mouthCy = (anchors.mouthCenter.y - 0.5) * 1.30 - CGFloat(open) * 0.05 + mouthOffset
        let mouthW = max(0.08, anchors.mouthSize.width * 0.75 * mouthScale)
        let mouthH = max(0.05, anchors.mouthSize.height * CGFloat(0.45 + open * 1.5) * mouthHeightScale)

        return zip(canonicalDiscMesh.positions, canonicalDiscMesh.uvs).map { position, uv in
            let px = CGFloat(position.x) * mouthW + mouthCx
            let py = CGFloat(position.y) * mouthH + mouthCy
            let depth = (0.06 + CGFloat(open) * 0.08) * jawDepthScale
            let edge = sqrt(Double(position.x * position.x + position.y * position.y))
            let pz = CGFloat(max(0, depth * (1 - edge)))
            let local = CGPoint3(
                x: px * expandedFaceBox.width,
                y: py * expandedFaceBox.height,
                z: pz * expandedFaceBox.width
            )
            let projected = projectPoint(local: local, center: center, yaw: yaw, pitch: pitch, roll: roll, perspective: perspective)
            return MeshVertex(
                clipPosition: simd_float3(
                    Float(projected.x * 2 - 1),
                    Float(projected.y * 2 - 1),
                    Float(projected.z * 0.002)
                ),
                uv: simd_float2(uv.x, uv.y),
                alpha: Float(max(0.35, 1 - edge * 0.45))
            )
        }
    }

    private func repeatedDiscIndices(instanceCount: Int) -> [UInt16] {
        guard instanceCount > 0 else { return [] }
        let verticesPerDisc = canonicalDiscMesh.positions.count
        var output: [UInt16] = []
        output.reserveCapacity(canonicalDiscMesh.indices.count * instanceCount)
        for instance in 0..<instanceCount {
            let base = instance * verticesPerDisc
            for index in canonicalDiscMesh.indices {
                output.append(UInt16(base) + index)
            }
        }
        return output
    }

    private func projectPoint(
        local: CGPoint3,
        center: CGPoint,
        yaw: CGFloat,
        pitch: CGFloat,
        roll: CGFloat,
        perspective: CGFloat
    ) -> CGPoint3 {
        let rotatedX = local.x * cos(yaw) + local.z * sin(yaw)
        let rotatedZ = -local.x * sin(yaw) + local.z * cos(yaw)
        let tiltedY = local.y * cos(pitch) - rotatedZ * sin(pitch)
        let zAfterPitch = local.y * sin(pitch) + rotatedZ * cos(pitch)
        let perspectiveScale = perspective / (perspective + zAfterPitch)
        let px = rotatedX * perspectiveScale
        let py = tiltedY * perspectiveScale
        let rx = px * cos(roll) - py * sin(roll)
        let ry = px * sin(roll) + py * cos(roll)
        return CGPoint3(x: center.x + rx, y: center.y + ry, z: zAfterPitch)
    }
}

private struct CGPoint3 {
    var x: CGFloat
    var y: CGFloat
    var z: CGFloat
}
