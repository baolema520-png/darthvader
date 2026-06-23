import CoreMedia
import CoreVideo
import Foundation

protocol VirtualCameraProviding: AnyObject {
    var isRunning: Bool { get }
    func start() throws
    func stop()
    func send(_ pixelBuffer: CVPixelBuffer, presentationTime: CMTime)
}
