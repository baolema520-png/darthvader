import AVFoundation
import Foundation

protocol AvatarEngineProviding: AnyObject {
    var avatarModel: AvatarModel? { get }
    func loadAvatar(from imageURL: URL) async throws
    func animateAvatar(with landmarks: FaceLandmarks?) -> AvatarMesh?
    func updateParameters(mouthSensitivity: Float, eyeSensitivity: Float, smoothing: Float)
    func updateIdentityParameters(
        faceWidth: Float,
        jawWidth: Float,
        eyeSpacing: Float,
        noseWidth: Float,
        mouthWidth: Float
    )
    func beginCalibration()
    func ingestCalibrationSample(_ landmarks: FaceLandmarks)
    func finishCalibration()
    func resetNeutralPose()
}
