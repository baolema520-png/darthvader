import CoreMediaIO
import Foundation

@available(macOS 12.3, *)
final class VirtualCameraExtensionProviderSource: NSObject, CMIOExtensionProviderSource {
    private(set) var provider: CMIOExtensionProvider!
    private let deviceSource = VirtualCameraExtensionDeviceSource()

    override init() {
        super.init()
        provider = CMIOExtensionProvider(source: self, clientQueue: .global(qos: .userInitiated))
        let device = CMIOExtensionDevice(
            localizedName: "520CAM",
            deviceID: UUID(),
            legacyDeviceID: "com.virtualfacecam.device.main",
            source: deviceSource
        )
        deviceSource.device = device
        deviceSource.attachStreamIfNeeded()
        _ = try? provider.addDevice(device)
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.providerName, .providerManufacturer]
    }

    func connect(to client: CMIOExtensionClient) throws {
        _ = client
    }

    func disconnect(from client: CMIOExtensionClient) {
        _ = client
    }

    func providerProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionProviderProperties {
        let props = CMIOExtensionProviderProperties(dictionary: [:])
        if properties.contains(.providerName) {
            props.name = "520CAM"
        }
        if properties.contains(.providerManufacturer) {
            props.manufacturer = "520CAM"
        }
        return props
    }

    func setProviderProperties(_ providerProperties: CMIOExtensionProviderProperties) throws {
        _ = providerProperties
    }
}
