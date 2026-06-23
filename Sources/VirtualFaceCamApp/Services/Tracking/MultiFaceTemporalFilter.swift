import Foundation

final class MultiFaceTemporalFilter {
    static let maxTrackedFaces = 2

    private var filters: [FaceTemporalFilter]

    init(alpha: Float = 0.80) {
        self.filters = (0..<Self.maxTrackedFaces).map { _ in FaceTemporalFilter(alpha: alpha) }
    }

    func reset() {
        filters.forEach { $0.reset() }
    }

    func filter(_ faces: [FaceLandmarks]) -> [FaceLandmarks] {
        let sorted = faces
            .sorted { $0.boundingBox.minX < $1.boundingBox.minX }
            .prefix(Self.maxTrackedFaces)

        return sorted.enumerated().map { index, face in
            filters[index].filter(face)
        }
    }
}
