import AVFoundation
import CoreMedia
import CoreMediaIO
import Foundation
import OSLog

@available(macOS 12.3, *)
final class VirtualCameraExtensionStreamSource: NSObject, CMIOExtensionStreamSource {
    weak var stream: CMIOExtensionStream?

    private let frameReader = SharedFrameReader()
    private let queue = DispatchQueue(label: "VirtualCameraExtension.StreamQueue", qos: .userInitiated)
    private let capture = ExtensionCameraCapture()
    private let logger = Logger(subsystem: "com.virtualfacecam.app.cameraextension", category: "VirtualCameraExtensionStream")
    private var timer: DispatchSourceTimer?
    private var currentFrameDuration: CMTime = CMTime(value: 1, timescale: 30)
    private var latestCameraSampleBuffer: CMSampleBuffer?
    private var capturedFrameCount: Int = 0
    private var sentFrameCount: Int = 0
    private var emptyTickCount: Int = 0

    var formats: [CMIOExtensionStreamFormat] {
        guard let desc = makeFormatDescription(width: 1280, height: 720) else { return [] }
        let format = CMIOExtensionStreamFormat(
            formatDescription: desc,
            maxFrameDuration: CMTime(value: 1, timescale: 30),
            minFrameDuration: CMTime(value: 1, timescale: 30),
            validFrameDurations: [CMTime(value: 1, timescale: 30)]
        )
        return [format]
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration, .streamMaxFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let props = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            props.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            props.frameDuration = currentFrameDuration
        }
        if properties.contains(.streamMaxFrameDuration) {
            props.maxFrameDuration = currentFrameDuration
        }
        return props
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        currentFrameDuration = streamProperties.frameDuration ?? currentFrameDuration
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        _ = client
        return true
    }

    func startStream() throws {
        guard timer == nil else { return }
        logger.info("startStream called")
        capture.onFrame = { [weak self] sampleBuffer in
            self?.latestCameraSampleBuffer = sampleBuffer
            guard let self else { return }
            self.capturedFrameCount += 1
            if self.capturedFrameCount.isMultiple(of: 60) {
                self.logger.info("Captured camera frames=\(self.capturedFrameCount, privacy: .public)")
            }
        }
        do {
            try capture.start()
        } catch {
            logger.error("Physical camera capture start failed: \(error.localizedDescription, privacy: .public)")
        }

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(2))
        timer.setEventHandler { [weak self] in
            self?.emitFrame()
        }
        self.timer = timer
        timer.resume()
    }

    func stopStream() throws {
        timer?.cancel()
        timer = nil
        capture.stop()
        latestCameraSampleBuffer = nil
    }
}

@available(macOS 12.3, *)
private extension VirtualCameraExtensionStreamSource {
    func emitFrame() {
        guard let stream else { return }
        guard let sampleBuffer = frameReader.readSampleBuffer() ?? latestCameraSampleBuffer else {
            emptyTickCount += 1
            if emptyTickCount.isMultiple(of: 60) {
                logger.error("No frame available. emptyTicks=\(self.emptyTickCount, privacy: .public) captured=\(self.capturedFrameCount, privacy: .public) sent=\(self.sentFrameCount, privacy: .public)")
            }
            return
        }
        let hostTimeNs = UInt64(DispatchTime.now().uptimeNanoseconds)
        stream.send(
            sampleBuffer,
            discontinuity: [],
            hostTimeInNanoseconds: hostTimeNs
        )
        sentFrameCount += 1
        if sentFrameCount.isMultiple(of: 60) {
            logger.info("Sent stream frames=\(self.sentFrameCount, privacy: .public) captured=\(self.capturedFrameCount, privacy: .public)")
        }
    }

    func makeFormatDescription(width: Int32, height: Int32) -> CMFormatDescription? {
        var desc: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: width,
            height: height,
            extensions: nil,
            formatDescriptionOut: &desc
        )
        guard status == noErr else { return nil }
        return desc
    }
}

@available(macOS 12.3, *)
private final class ExtensionCameraCapture: NSObject {
    var onFrame: ((CMSampleBuffer) -> Void)?

    private let session = AVCaptureSession()
    private let output = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "VirtualCameraExtension.CaptureQueue", qos: .userInitiated)
    private let logger = Logger(subsystem: "com.virtualfacecam.app.cameraextension", category: "ExtensionCameraCapture")

    func start() throws {
        if session.isRunning { return }
        if session.inputs.isEmpty {
            try configure()
        }
        session.startRunning()
    }

    func stop() {
        if session.isRunning {
            session.stopRunning()
        }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if session.canSetSessionPreset(.hd1280x720) {
            session.sessionPreset = .hd1280x720
        } else {
            session.sessionPreset = .high
        }

        let devices = preferredPhysicalDevices()
        guard !devices.isEmpty else {
            throw NSError(domain: "VirtualCameraExtension", code: 1, userInfo: [NSLocalizedDescriptionKey: "No physical camera device found"])
        }

        var inputAdded = false
        var lastError: Error?
        for device in devices {
            logger.info("Trying capture device name=\(device.localizedName, privacy: .public) id=\(device.uniqueID, privacy: .public)")
            do {
                let input = try AVCaptureDeviceInput(device: device)
                guard session.canAddInput(input) else { continue }
                session.addInput(input)
                logger.info("Using capture device name=\(device.localizedName, privacy: .public)")
                inputAdded = true
                break
            } catch {
                lastError = error
            }
        }
        guard inputAdded else {
            throw NSError(
                domain: "VirtualCameraExtension",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to add capture input. Last error: \(lastError?.localizedDescription ?? "unknown")"]
            )
        }

        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            throw NSError(domain: "VirtualCameraExtension", code: 3, userInfo: [NSLocalizedDescriptionKey: "Unable to add capture output"])
        }
        session.addOutput(output)
    }

    private func preferredPhysicalDevices() -> [AVCaptureDevice] {
        let builtIn = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera],
            mediaType: .video,
            position: .unspecified
        ).devices
        let external = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.externalUnknown],
            mediaType: .video,
            position: .unspecified
        ).devices
        // Prioriza camara integrada (FaceTime) para evitar virtuales de terceros.
        let candidates = (builtIn + external).filter { device in
            let id = device.uniqueID.lowercased()
            let name = device.localizedName.lowercased()
            let model = device.modelID.lowercased()
            let isVirtual =
                id.contains("virtualfacecam") ||
                id.contains("filteronme") ||
                id.contains("manycam") ||
                name.contains("virtualfacecam") ||
                name.contains("filteronme") ||
                name.contains("manycam") ||
                model.contains("filteronme") ||
                model.contains("manycam") ||
                model.contains("virtualfacecam") ||
                name.contains("camera extension")
            return !isVirtual
        }
        let front = candidates.filter { $0.position == .front }
        let rest = candidates.filter { $0.position != .front }
        return front + rest
    }
}

@available(macOS 12.3, *)
extension ExtensionCameraCapture: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        _ = output
        _ = connection
        onFrame?(sampleBuffer)
    }
}
