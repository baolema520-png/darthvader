import Foundation
import simd

struct CanonicalMeshData: Sendable {
    var positions: [simd_float3]
    var uvs: [simd_float2]
    var indices: [UInt16]
}

enum CanonicalHeadGeometry {
    static func makeHeadMesh(columns: Int = 36, rows: Int = 28) -> CanonicalMeshData {
        var positions: [simd_float3] = []
        var uvs: [simd_float2] = []
        var indices: [UInt16] = []

        for row in 0...rows {
            let v = Float(row) / Float(rows)
            let phi = (v - 0.5) * .pi
            let y = sin(phi) * 0.62
            let ring = cos(phi)

            for col in 0...columns {
                let u = Float(col) / Float(columns)
                let theta = (u - 0.5) * (.pi * 2)
                let x = sin(theta) * ring * 0.52
                let z = cos(theta) * ring * 0.42
                positions.append(simd_float3(x, y, z))
                uvs.append(simd_float2(u, 1 - v))
            }
        }

        let stride = columns + 1
        for row in 0..<rows {
            for col in 0..<columns {
                let a = UInt16(row * stride + col)
                let b = UInt16(row * stride + col + 1)
                let c = UInt16((row + 1) * stride + col)
                let d = UInt16((row + 1) * stride + col + 1)
                indices.append(a); indices.append(c); indices.append(b)
                indices.append(b); indices.append(c); indices.append(d)
            }
        }
        return CanonicalMeshData(positions: positions, uvs: uvs, indices: indices)
    }

    static func makeDiscMesh(segments: Int = 24, radiusX: Float = 1.0, radiusY: Float = 1.0) -> CanonicalMeshData {
        var positions: [simd_float3] = [simd_float3(0, 0, 0)]
        var uvs: [simd_float2] = [simd_float2(0.5, 0.5)]
        var indices: [UInt16] = []

        for i in 0...segments {
            let t = Float(i) / Float(segments) * (.pi * 2)
            let x = cos(t) * radiusX
            let y = sin(t) * radiusY
            positions.append(simd_float3(x, y, 0))
            uvs.append(simd_float2(0.5 + x * 0.5, 0.5 + y * 0.5))
            if i > 0 {
                indices.append(0)
                indices.append(UInt16(i))
                indices.append(UInt16(i + 1))
            }
        }
        return CanonicalMeshData(positions: positions, uvs: uvs, indices: indices)
    }
}
