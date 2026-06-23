import AVFoundation
import CoreImage
import Foundation

protocol RenderingProviding: AnyObject {
    func render(
        sourceFrame: CVPixelBuffer,
        trackingMode: TrackingMode,
        blurIntensity: Float,
        pixelationIntensity: Float,
        backgroundMode: VirtualBackgroundMode,
        backgroundBlurIntensity: Float,
        backgroundColor: CIColor,
        backgroundImageURL: URL?,
        avatarModel: AvatarModel?,
        animatedMesh: AvatarMesh?,
        landmarks: FaceLandmarks?
    ) -> CVPixelBuffer?
}
