import CoreMediaIO
import Foundation

if #available(macOS 12.3, *) {
    let providerSource = VirtualCameraExtensionProviderSource()
    CMIOExtensionProvider.startService(provider: providerSource.provider)
    RunLoop.main.run()
}
