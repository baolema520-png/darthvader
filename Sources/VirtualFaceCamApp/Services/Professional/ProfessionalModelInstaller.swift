import Foundation

final class ProfessionalModelInstaller {
    private let assetManager: ProfessionalModelAssetManager
    private let fm = FileManager.default

    init(assetManager: ProfessionalModelAssetManager = .shared) {
        self.assetManager = assetManager
    }

    func installAvailableModels() async throws -> [String] {
        try assetManager.ensureModelDirectory()
        var installed: [String] = []

        for spec in assetManager.expectedModels {
            if assetManager.existingFileName(for: spec) != nil {
                installed.append(spec.identifier)
                continue
            }
            if let bundled = assetManager.bundledModelURL(for: spec) {
                let destination = assetManager.modelsDirectory.appendingPathComponent(bundled.resolvedFileName)
                try copyModel(from: bundled.sourceURL, to: destination)
                installed.append(spec.identifier)
            }
        }

        return installed
    }

    private func copyModel(from source: URL, to destination: URL) throws {
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: source, to: destination)
    }
}
