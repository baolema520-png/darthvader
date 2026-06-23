import CoreMedia
import CoreVideo
import Foundation

public final class DALFrameBridge {
    public static let shared = DALFrameBridge()

    private let queue = DispatchQueue(label: "DALFrameBridge.Queue", qos: .userInitiated)
    private var latestFrame: (buffer: CVPixelBuffer, time: CMTime)?

    private init() {}

    public func push(pixelBuffer: CVPixelBuffer, time: CMTime) {
        queue.async {
            self.latestFrame = (pixelBuffer, time)
        }
    }

    public func pullLatestFrame() -> (buffer: CVPixelBuffer, time: CMTime)? {
        queue.sync { latestFrame }
    }
}
