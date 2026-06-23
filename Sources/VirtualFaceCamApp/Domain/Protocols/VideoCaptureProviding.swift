import AVFoundation
import Foundation

protocol VideoCaptureProviding: AnyObject {
    var onFrame: ((CMSampleBuffer) -> Void)? { get set }
    func startCapture() throws
    func stopCapture()
}
