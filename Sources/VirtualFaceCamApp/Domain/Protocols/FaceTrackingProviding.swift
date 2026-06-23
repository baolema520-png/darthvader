import AVFoundation
import Foundation

protocol FaceTrackingProviding: AnyObject {
    var onLandmarks: (([FaceLandmarks]) -> Void)? { get set }
    func process(sampleBuffer: CMSampleBuffer)
}
