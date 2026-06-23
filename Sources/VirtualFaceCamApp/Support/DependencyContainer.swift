import Foundation

struct DependencyContainer {
    let videoCapture: VideoCaptureProviding
    let faceTracking: FaceTrackingProviding
    let avatarEngine: AvatarEngineProviding
    let renderer: RenderingProviding
    let virtualCamera: VirtualCameraProviding
    let professionalFacePipeline: ProfessionalFacePipeline

    static let live: DependencyContainer = {
        let professionalFacePipeline = ProfessionalFacePipeline.shared
        return DependencyContainer(
            videoCapture: VideoCaptureManager(),
            faceTracking: FaceTrackingService(professionalPipeline: professionalFacePipeline),
            avatarEngine: AvatarEngine(),
            renderer: RenderingEngine(),
            virtualCamera: VirtualCameraOutput(),
            professionalFacePipeline: professionalFacePipeline
        )
    }()
}
