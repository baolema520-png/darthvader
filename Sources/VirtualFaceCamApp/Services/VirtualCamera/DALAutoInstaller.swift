import AppKit
import Foundation

enum DALAutoInstallerError: Error, LocalizedError {
    case bundledPluginNotFound
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundledPluginNotFound:
            return "No se encontro el plugin DAL dentro de la app."
        case .installFailed(let details):
            return "No se pudo instalar el plugin DAL: \(details)"
        }
    }
}

final class DALAutoInstaller {
    private let installPath = "/Library/CoreMediaIO/Plug-Ins/DAL/VirtualFaceCamDALPlugin.plugin"

    func isInstalledAndUpToDate() -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: installPath) else { return false }

        guard
            let bundled = bundledPluginURL(),
            let bundledInfo = NSDictionary(contentsOf: bundled.appendingPathComponent("Contents/Info.plist")) as? [String: Any],
            let installedInfo = NSDictionary(contentsOf: URL(fileURLWithPath: "\(installPath)/Contents/Info.plist")) as? [String: Any]
        else {
            return true
        }

        let bundledVersion = (bundledInfo["CFBundleVersion"] as? String) ?? "0"
        let installedVersion = (installedInfo["CFBundleVersion"] as? String) ?? "0"
        return bundledVersion == installedVersion
    }

    func installIfNeeded() throws {
        if isInstalledAndUpToDate() { return }
        guard let bundled = bundledPluginURL() else {
            throw DALAutoInstallerError.bundledPluginNotFound
        }

        let command = makeInstallCommand(from: bundled.path)
        let source = "do shell script \"\(command)\" with administrator privileges"
        var errorInfo: NSDictionary?
        NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)

        if let errorInfo {
            let details = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Error desconocido"
            throw DALAutoInstallerError.installFailed(details)
        }
    }

    private func bundledPluginURL() -> URL? {
        let pluginName = "VirtualFaceCamDALPlugin.plugin"
        let candidates = [
            Bundle.main.builtInPlugInsURL?.appendingPathComponent(pluginName),
            Bundle.main.resourceURL?.appendingPathComponent(pluginName)
        ].compactMap { $0 }

        for candidate in candidates where FileManager.default.fileExists(atPath: candidate.path) {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                continue
            }
            return candidate
        }
        return nil
    }

    private func makeInstallCommand(from bundledPath: String) -> String {
        let escapedBundled = shellEscape(bundledPath)
        let escapedTarget = shellEscape(installPath)
        return [
            "mkdir -p /Library/CoreMediaIO/Plug-Ins/DAL",
            "rm -rf \(escapedTarget)",
            "cp -R \(escapedBundled) /Library/CoreMediaIO/Plug-Ins/DAL/",
            "chown -R root:wheel \(escapedTarget)",
            "chmod -R 755 \(escapedTarget)",
            "killall -9 VDCAssistant || true",
            "killall -9 AppleCameraAssistant || true"
        ].joined(separator: "; ")
    }

    private func shellEscape(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
