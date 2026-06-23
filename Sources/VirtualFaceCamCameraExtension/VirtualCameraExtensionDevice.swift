import CoreMediaIO
import Foundation

@available(macOS 12.3, *)
final class VirtualCameraExtensionDeviceSource: NSObject, CMIOExtensionDeviceSource {
    weak var device: CMIOExtensionDevice?
    private let streamSource = VirtualCameraExtensionStreamSource()
    private(set) var stream: CMIOExtensionStream?

    override init() {
        super.init()
        let stream = CMIOExtensionStream(
            localizedName: "520CAM Stream",
            streamID: UUID(),
            direction: .source,
            clockType: .hostTime,
            source: streamSource
        )
        self.stream = stream
        self.streamSource.stream = stream
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.deviceModel, .deviceTransportType]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let props = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceModel) {
            props.model = "520CAM"
        }
        if properties.contains(.deviceTransportType) {
            props.transportType = 0
        }
        return props
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {
        _ = deviceProperties
    }

    func attachStreamIfNeeded() {
        guard let device, let stream else { return }
        _ = try? device.addStream(stream)
    }
}
