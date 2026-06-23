import Foundation

final class ProfessionalModelAssetManager {
    struct ModelSpec: Sendable, Equatable {
        let identifier: String
        let fileName: String
        let alternativeFileNames: [String]
        let purpose: String
        let origin: String
        let redistribution: String
        let isRequiredForReady: Bool
    }

    static let shared = ProfessionalModelAssetManager()

    let expectedModels: [ModelSpec] = [
        ModelSpec(
            identifier: "face_detector",
            fileName: "faceboxesv2-640x640.onnx",
            alternativeFileNames: [
                "version-RFB-640.onnx",
                "version-RFB-320.onnx",
                "ultraface_version_rfb_640.onnx"
            ],
            purpose: "deteccion facial rapida para pipeline denso local",
            origin: "FaceBoxes / UltraFace compatibles",
            redistribution: "FaceBoxes Apache-2.0 o UltraFace MIT redistribuibles dentro del bundle",
            isRequiredForReady: true
        ),
        ModelSpec(
            identifier: "dense_fitting",
            fileName: "3ddfa_mb05_bfm_head.onnx",
            alternativeFileNames: [
                "dense_head_pose_face_mesh.onnx",
                "3d_face_reconstruction.onnx"
            ],
            purpose: "referencia opcional para fitting denso; la app usa replica interna",
            origin: "Replica interna compatible integrada en Swift",
            redistribution: "no requerido para funcionamiento del producto final",
            isRequiredForReady: false
        ),
        ModelSpec(
            identifier: "identity_regressor",
            fileName: "faceverse_resnet50_identity.onnx",
            alternativeFileNames: [
                "face-recognition-resnet100-arcface-onnx.onnx",
                "arcfaceresnet100-8.onnx"
            ],
            purpose: "referencia opcional para identidad; la app usa replica interna",
            origin: "Replica interna FaceVerse/DECA-style integrada en Swift",
            redistribution: "no requerido para funcionamiento del producto final",
            isRequiredForReady: false
        ),
        ModelSpec(
            identifier: "mediapipe_face_landmarker",
            fileName: "face_landmarker.task",
            alternativeFileNames: [],
            purpose: "malla facial densa oficial MediaPipe",
            origin: "MediaPipe oficial",
            redistribution: "Apache 2.0 redistribuible dentro del bundle",
            isRequiredForReady: false
        )
    ]

    private let fm = FileManager.default

    var modelsDirectory: URL {
        let appSupport = (try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )) ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return appSupport.appendingPathComponent("VirtualFaceCam/Models", isDirectory: true)
    }

    func ensureModelDirectory() throws {
        try fm.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
    }

    func modelURL(for identifier: String) -> URL? {
        guard let spec = expectedModels.first(where: { $0.identifier == identifier }) else { return nil }
        if let existing = existingFileName(for: spec) {
            return modelsDirectory.appendingPathComponent(existing)
        }
        return modelsDirectory.appendingPathComponent(spec.fileName)
    }

    func existingModels() -> [String] {
        expectedModels.compactMap { spec in
            existingFileName(for: spec) != nil ? spec.identifier : nil
        }
    }

    func missingModels() -> [String] {
        expectedModels.compactMap { spec in
            guard spec.isRequiredForReady else { return nil }
            return existingFileName(for: spec) == nil ? spec.identifier : nil
        }
    }

    func bundledModelURL(for fileName: String) -> URL? {
        Bundle.main.url(forResource: fileName, withExtension: nil, subdirectory: "Models")
    }

    func bundledModelURL(for spec: ModelSpec) -> (sourceURL: URL, resolvedFileName: String)? {
        for fileName in [spec.fileName] + spec.alternativeFileNames {
            if let bundled = bundledModelURL(for: fileName) {
                return (bundled, fileName)
            }
        }
        return nil
    }

    func existingFileName(for spec: ModelSpec) -> String? {
        for fileName in [spec.fileName] + spec.alternativeFileNames {
            let url = modelsDirectory.appendingPathComponent(fileName)
            if fm.fileExists(atPath: url.path) {
                return fileName
            }
        }
        return nil
    }
}
