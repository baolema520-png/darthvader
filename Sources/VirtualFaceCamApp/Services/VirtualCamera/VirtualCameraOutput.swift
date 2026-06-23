import CoreMedia
import Foundation

final class VirtualCameraOutput: VirtualCameraProviding {
    private(set) var isRunning: Bool = false
    private let queue = DispatchQueue(label: "VirtualCameraOutput.Queue", qos: .userInitiated)
    private(set) var latestFrame: CVPixelBuffer?
    private(set) var latestPresentationTime: CMTime = .zero
    private let sharedFrameWriter = SharedFrameWriter()

    func start() throws {
        isRunning = true
    }

    func stop() {
        isRunning = false
    }

    func send(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        guard isRunning else { return }
        queue.async {
            self.latestFrame = pixelBuffer
            self.latestPresentationTime = presentationTime
            self.sharedFrameWriter.write(pixelBuffer: pixelBuffer, time: presentationTime)
            // Aqui tambien se conecta el puente en memoria de proceso para scaffold.
        }
    }
}
