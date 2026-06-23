import CoreGraphics
import Foundation

final class MeshGenerator {
    func generateMesh(from points: [CGPoint]) -> AvatarMesh {
        let deduped = uniquePoints(points)
        let vertices = deduped.map { point in
            AvatarVertex(position: point.clampedUnit, uv: point.clampedUnit)
        }
        let positions = vertices.map(\.position)
        let triangles = delaunayTriangles(for: positions)
        var indices = triangles.flatMap { [UInt16($0.a), UInt16($0.b), UInt16($0.c)] }
        if indices.isEmpty, positions.count >= 3 {
            // Fallback robusto: garantiza triangulos aunque Delaunay falle en casos degenerados.
            indices = fanTriangulationIndices(for: positions)
        }
        return AvatarMesh(vertices: vertices, indices: indices)
    }
}

private extension MeshGenerator {
    struct Edge: Hashable {
        let u: Int
        let v: Int

        init(_ a: Int, _ b: Int) {
            if a < b {
                self.u = a
                self.v = b
            } else {
                self.u = b
                self.v = a
            }
        }
    }

    struct Triangle: Hashable {
        let a: Int
        let b: Int
        let c: Int
        var edges: [Edge] { [Edge(a, b), Edge(b, c), Edge(c, a)] }
    }

    func uniquePoints(_ points: [CGPoint]) -> [CGPoint] {
        var set = Set<String>()
        var result: [CGPoint] = []
        for point in points {
            let clamped = point.clampedUnit
            let key = "\(Int(clamped.x * 2000))_\(Int(clamped.y * 2000))"
            if set.insert(key).inserted {
                result.append(clamped)
            }
        }
        return result
    }

    func delaunayTriangles(for points: [CGPoint]) -> [Triangle] {
        guard points.count >= 3 else { return [] }

        var workPoints = points
        let superTriangle = makeSuperTriangle(points)
        workPoints.append(contentsOf: superTriangle)

        let superA = workPoints.count - 3
        let superB = workPoints.count - 2
        let superC = workPoints.count - 1

        var triangulation: Set<Triangle> = [Triangle(a: superA, b: superB, c: superC)]

        for index in 0..<points.count {
            let point = workPoints[index]
            var badTriangles: [Triangle] = []
            for triangle in triangulation where circumcircleContains(triangle, point: point, points: workPoints) {
                badTriangles.append(triangle)
            }

            var polygon = [Edge: Int]()
            for triangle in badTriangles {
                triangulation.remove(triangle)
                for edge in triangle.edges {
                    polygon[edge, default: 0] += 1
                }
            }

            let boundaryEdges = polygon.filter { $0.value == 1 }.map(\.key)
            for edge in boundaryEdges {
                triangulation.insert(Triangle(a: edge.u, b: edge.v, c: index))
            }
        }

        return triangulation.filter { triangle in
            ![superA, superB, superC].contains(triangle.a)
            && ![superA, superB, superC].contains(triangle.b)
            && ![superA, superB, superC].contains(triangle.c)
        }
    }

    func makeSuperTriangle(_ points: [CGPoint]) -> [CGPoint] {
        let minX = points.map(\.x).min() ?? 0
        let maxX = points.map(\.x).max() ?? 1
        let minY = points.map(\.y).min() ?? 0
        let maxY = points.map(\.y).max() ?? 1

        let dx = maxX - minX
        let dy = maxY - minY
        let delta = max(dx, dy) * 10
        let midX = (minX + maxX) / 2
        let midY = (minY + maxY) / 2

        return [
            CGPoint(x: midX - 2 * delta, y: midY - delta),
            CGPoint(x: midX, y: midY + 2 * delta),
            CGPoint(x: midX + 2 * delta, y: midY - delta)
        ]
    }

    func circumcircleContains(_ triangle: Triangle, point: CGPoint, points: [CGPoint]) -> Bool {
        let a = points[triangle.a]
        let b = points[triangle.b]
        let c = points[triangle.c]

        let ax = Double(a.x - point.x)
        let ay = Double(a.y - point.y)
        let bx = Double(b.x - point.x)
        let by = Double(b.y - point.y)
        let cx = Double(c.x - point.x)
        let cy = Double(c.y - point.y)

        let determinant =
            (ax * ax + ay * ay) * (bx * cy - cx * by)
            - (bx * bx + by * by) * (ax * cy - cx * ay)
            + (cx * cx + cy * cy) * (ax * by - bx * ay)

        let orientation = (Double(b.x - a.x) * Double(c.y - a.y)) - (Double(b.y - a.y) * Double(c.x - a.x))
        return orientation >= 0 ? determinant > 0 : determinant < 0
    }

    func fanTriangulationIndices(for points: [CGPoint]) -> [UInt16] {
        guard points.count >= 3 else { return [] }
        let center = CGPoint(
            x: points.map(\.x).reduce(0, +) / CGFloat(points.count),
            y: points.map(\.y).reduce(0, +) / CGFloat(points.count)
        )
        let ordered = points.enumerated().sorted { lhs, rhs in
            let a0 = atan2(lhs.element.y - center.y, lhs.element.x - center.x)
            let a1 = atan2(rhs.element.y - center.y, rhs.element.x - center.x)
            return a0 < a1
        }.map(\.offset)

        guard ordered.count >= 3 else { return [] }
        var output: [UInt16] = []
        output.reserveCapacity((ordered.count - 2) * 3)
        for i in 1..<(ordered.count - 1) {
            output.append(UInt16(ordered[0]))
            output.append(UInt16(ordered[i]))
            output.append(UInt16(ordered[i + 1]))
        }
        return output
    }
}

private extension CGPoint {
    var clampedUnit: CGPoint {
        CGPoint(x: min(max(x, 0), 1), y: min(max(y, 0), 1))
    }
}
