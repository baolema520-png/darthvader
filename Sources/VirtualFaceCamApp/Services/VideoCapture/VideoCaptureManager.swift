import AVFoundation
import Foundation

final class VideoCaptureManager: NSObject, VideoCaptureProviding {
    enum CaptureError: Error, LocalizedError {
        case cameraUnavailable
        case permissionDenied
        case inputCreationFailed
        case outputConfigurationFailed

        var errorDescription: String? {
            switch self {
            case .cameraUnavailable:
                return "No se encontro ninguna camara fisica disponible."
            case .permissionDenied:
                return "520CAM needs camera access. In System Settings > Privacy & Security > Camera, enable 520CAM. If you only see VirtualFaceCamApp, remove the old app from Applications and open 520CAM again."
            case .inputCreationFailed:
                return "No se pudo crear la entrada de video de la camara."
            case .outputConfigurationFailed:
                return "No se pudo configurar la salida de video de la camara."
            }
        }
    }

    var onFrame: ((CMSampleBuffer) -> Void)?

    private let session = AVCaptureSession()
    private let outputQueue = DispatchQueue(label: "VideoCaptureManager.OutputQueue", qos: .userInitiated)
    private let videoOutput = AVCaptureVideoDataOutput()

    func startCapture() throws {
        guard !session.isRunning else { return }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            var granted = false
            let semaphore = DispatchSemaphore(value: 0)
            AVCaptureDevice.requestAccess(for: .video) { allowed in
                granted = allowed
                semaphore.signal()
            }
            semaphore.wait()
            guard granted else { throw CaptureError.permissionDenied }
        case .denied, .restricted:
            throw CaptureError.permissionDenied
        @unknown default:
            throw CaptureError.permissionDenied
        }

        try configureSessionIfNeeded()
        session.startRunning()
    }

    func stopCapture() {
        guard session.isRunning else { return }
        session.stopRunning()
    }

    private func configureSessionIfNeeded() throws {
        guard session.inputs.isEmpty, session.outputs.isEmpty else { return }
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .high
        }

        guard let device = preferredCaptureDevice() else {
            throw CaptureError.cameraUnavailable
        }
        try configureDevice(device)

        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else {
            throw CaptureError.inputCreationFailed
        }
        session.addInput(input)

        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

        guard session.canAddOutput(videoOutput) else {
            throw CaptureError.outputConfigurationFailed
        }
        session.addOutput(videoOutput)

    }

    private func preferredCaptureDevice() -> AVCaptureDevice? {
        // Evita el bucle de retroalimentacion: la app nunca debe capturar su propia camara virtual.
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .externalUnknown],
            mediaType: .video,
            position: .unspecified
        )
        let physicalDevices = discovery.devices.filter { device in
            let id = device.uniqueID.lowercased()
            let name = device.localizedName.lowercased()
            return !id.contains("com.virtualfacecam") && !name.contains("virtualfacecam") && !name.contains("520cam")
        }

        if let front = physicalDevices.first(where: { $0.position == .front }) {
            return front
        }
        return physicalDevices.first
    }

    private func configureDevice(_ device: AVCaptureDevice) throws {
        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }

        if let format720p = device.formats.first(where: { format in
            let dimensions = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard dimensions.width == 1280, dimensions.height == 720 else { return false }
            return format.videoSupportedFrameRateRanges.contains { $0.maxFrameRate >= 30 }
        }) {
            device.activeFormat = format720p
        }

        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 30)
        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 30)
    }
}

extension VideoCaptureManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        onFrame?(sampleBuffer)
    }
}
