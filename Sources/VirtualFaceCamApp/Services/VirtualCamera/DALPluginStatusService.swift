import Foundation

struct DALPluginStatus {
    let isInstalled: Bool
    let bundleIdentifier: String?
    let version: String?
    let installPath: String
}

final class DALPluginStatusService {
    private let pluginPath = "/Library/CoreMediaIO/Plug-Ins/DAL/VirtualFaceCamDALPlugin.plugin"

    func currentStatus() -> DALPluginStatus {
        let exists = FileManager.default.fileExists(atPath: pluginPath)
        guard exists else {
            return DALPluginStatus(
                isInstalled: false,
                bundleIdentifier: nil,
                version: nil,
                installPath: pluginPath
            )
        }

        let infoPath = "\(pluginPath)/Contents/Info.plist"
        let info = NSDictionary(contentsOfFile: infoPath) as? [String: Any]
        let bundleIdentifier = info?["CFBundleIdentifier"] as? String
        let version = (info?["CFBundleShortVersionString"] as? String) ?? (info?["CFBundleVersion"] as? String)

        return DALPluginStatus(
            isInstalled: true,
            bundleIdentifier: bundleIdentifier,
            version: version,
            installPath: pluginPath
        )
    }
}
