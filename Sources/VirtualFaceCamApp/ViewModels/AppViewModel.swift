import AppKit
import AVFoundation
import Combine
import CoreImage
import Foundation
import OSLog

final class AppViewModel: ObservableObject {
    @Published var selectedMode: TrackingMode = .blur
    @Published var blurIntensity: Double = 12
    @Published var pixelationIntensity: Double = 18
    @Published var backgroundMode: VirtualBackgroundMode = .none
    @Published var backgroundBlurIntensity: Double = 18
    @Published var backgroundColorPreset: VirtualBackgroundColorPreset = .dark
    @Published var backgroundImageURL: URL?
    @Published var isCameraActive: Bool = false
    @Published var isTrackingActive: Bool = false
    @Published var statusText: String = "Ready"
    @Published var previewImage: NSImage?
    @Published var isDALInstalled: Bool = false
    @Published var dalStatusText: String = "DAL plugin status unknown"
    @Published var isInstallingDAL: Bool = false
    @Published var extensionStatusText: String = "Extension de camara pendiente de activar"
    @Published var isActivatingExtension: Bool = false
    @Published var isInstallingProfessionalModels: Bool = false
    @Published var professionalPipelineText: String = "Pipeline pro pendiente"
    @Published var debugTrackingText: String = "-"
    @Published var debugPerformanceText: String = "-"
    @Published var isDebugModeEnabled: Bool = false
    @Published var showInstallLocationWarning: Bool = false

    private let container: DependencyContainer
    private let processingQueue = DispatchQueue(label: "AppViewModel.ProcessingQueue", qos: .userInitiated)
    private let stateQueue = DispatchQueue(label: "AppViewModel.StateQueue", qos: .userInitiated)
    private let frameProcessingSemaphore = DispatchSemaphore(value: 1)
    private let previewContext = CIContext()
    private var latestLandmarks: [FaceLandmarks] = []
    private var frameCounter: Int = 0
    private let dalStatusService = DALPluginStatusService()
    private let dalAutoInstaller = DALAutoInstaller()
    private let professionalModelInstaller = ProfessionalModelInstaller()
    private let cameraExtensionInstaller = CameraExtensionInstaller()
    private let logger = Logger(subsystem: "com.virtualfacecam.app", category: "AppViewModel")
    private var didAttemptAutoExtensionActivation = false
    init(container: DependencyContainer) {
        self.container = container
        bindPipeline()
        refreshDALStatus()
        refreshProfessionalPipelineStatus()
        installBundledProfessionalModelsOnLaunch()
        logger.info("AppViewModel initialized")
        ensureCameraExtensionActivatedOnLaunch()
        if !isRunningFromApplications {
            showInstallLocationWarning = true
        }
    }

    func start() {
        do {
            try container.videoCapture.startCapture()
            try? container.virtualCamera.start()
            isCameraActive = true
            statusText = "Camera running"
        } catch let error as VideoCaptureManager.CaptureError {
            statusText = error.localizedDescription ?? "Error starting camera"
            if case .permissionDenied = error {
                showCameraPermissionHelp()
            }
        } catch {
            statusText = "Error starting camera: \(error.localizedDescription)"
        }
    }

    func stop() {
        container.videoCapture.stopCapture()
        container.virtualCamera.stop()
        isCameraActive = false
        isTrackingActive = false
        statusText = "Stopped"
    }

    func toggleVirtualCamera() {
        refreshDALStatus()

        if container.virtualCamera.isRunning {
            container.virtualCamera.stop()
            statusText = "Virtual camera stopped"
            return
        }

        do {
            try container.virtualCamera.start()
            statusText = "Virtual camera started"
        } catch {
            statusText = "Virtual camera failed: \(error.localizedDescription)"
        }
    }

    var isRunningFromApplications: Bool {
        Bundle.main.bundleURL.path.hasPrefix("/Applications/")
    }

    func openApplicationsFolder() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications"))
    }

    func openPrivacySecuritySettings() {
        openSystemSettingsURL("x-apple.systempreferences:com.apple.settings.PrivacySecurity")
    }

    func openCameraPrivacySettings() {
        openSystemSettingsURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
    }

    func showCameraPermissionHelp() {
        openCameraPrivacySettings()

        let panel = NSAlert()
        panel.messageText = "Enable camera for 520CAM"
        panel.informativeText = """
        macOS may still list the old name "VirtualFaceCamApp" in Camera settings.

        1. Open System Settings > Privacy & Security > Camera.
        2. Enable 520CAM (or VirtualFaceCamApp if that is the only entry).
        3. If it still fails, delete any old VirtualFaceCamApp from Applications, reinstall 520CAM, and press Start again.
        """
        panel.alertStyle = .informational
        panel.addButton(withTitle: "OK")
        panel.runModal()
    }

    func openSetupGuide() {
        if let bundledGuide = Bundle.main.url(forResource: "guide-en", withExtension: "html") {
            NSWorkspace.shared.open(bundledGuide)
            return
        }

        let panel = NSAlert()
        panel.messageText = "Setup guide not found"
        panel.informativeText = "Open the \"Start Here\" app from the 520CAM disk image."
        panel.alertStyle = .informational
        panel.addButton(withTitle: "OK")
        panel.runModal()
    }

    func installDALAutomatically() {
        isInstallingDAL = true
        statusText = "Instalando DAL..."

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try self.dalAutoInstaller.installIfNeeded()
                DispatchQueue.main.async {
                    self.refreshDALStatus()
                    self.isInstallingDAL = false
                    self.statusText = self.isDALInstalled ? "DAL instalado correctamente" : "DAL no instalado"
                }
            } catch {
                DispatchQueue.main.async {
                    self.isInstallingDAL = false
                    self.statusText = "Fallo instalacion DAL: \(error.localizedDescription)"
                }
            }
        }
    }

    func ensureDALInstalledOnLaunch() {
        refreshDALStatus()
        guard !isDALInstalled else { return }
        installDALAutomatically()
    }

    func ensureCameraExtensionActivatedOnLaunch() {
        guard !didAttemptAutoExtensionActivation else { return }
        didAttemptAutoExtensionActivation = true

        let appPath = Bundle.main.bundleURL.path
        logger.info("Auto activation check. appPath=\(appPath, privacy: .public)")
        guard appPath.hasPrefix("/Applications/") else {
            extensionStatusText = "Extension pendiente (abre la app desde /Applications)"
            logger.error("Auto activation skipped: app not under /Applications")
            return
        }

        logger.info("Auto activation starting")
        activateCameraExtension()
    }

    func activateCameraExtension() {
        isActivatingExtension = true
        cameraExtensionInstaller.activateIfNeeded(stateHandler: { [weak self] state in
            guard let self else { return }
            DispatchQueue.main.async {
                switch state {
                case .submitting:
                    self.extensionStatusText = "Activando extension de camara..."
                case .needsUserApproval:
                    self.extensionStatusText = "Aprobacion requerida: Ajustes del sistema > Privacidad y seguridad"
                case .completed:
                    self.extensionStatusText = "Extension de camara activa"
                case .failed(let message):
                    self.extensionStatusText = "Error extension: \(message)"
                }
            }
        }, completion: { [weak self] result in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isActivatingExtension = false
            }
            switch result {
            case .success:
                DispatchQueue.main.async {
                    self.extensionStatusText = "Extension de camara activa"
                }
            case .failure(let error):
                // El mensaje detallado se publica en stateHandler(.failed)
                // para preservar domain/codigo/motivo del error nativo.
                _ = error
            }
        })
    }

    func refreshDALStatus() {
        let status = dalStatusService.currentStatus()
        isDALInstalled = status.isInstalled
        if status.isInstalled {
            let versionText = status.version ?? "unknown"
            dalStatusText = "DAL instalado (v\(versionText))"
        } else {
            dalStatusText = "DAL no instalado: \(status.installPath)"
        }
    }

    func refreshProfessionalPipelineStatus() {
        let status = container.professionalFacePipeline.status
        professionalPipelineText = "\(status.summary) | backend: \(container.professionalFacePipeline.trackingBackendDescription())"
    }

    func installProfessionalModels() {
        guard !isInstallingProfessionalModels else { return }
        isInstallingProfessionalModels = true
        statusText = "Instalando recursos internos bundleados..."
        Task {
            do {
                let installed = try await professionalModelInstaller.installAvailableModels()
                await MainActor.run {
                    self.isInstallingProfessionalModels = false
                    self.refreshProfessionalPipelineStatus()
                    if installed.isEmpty {
                        self.statusText = "No habia recursos internos nuevos. El pipeline autocontenido ya esta listo."
                    } else {
                        self.statusText = "Recursos internos instalados/confirmados: \(installed.joined(separator: ", "))"
                    }
                }
            } catch {
                await MainActor.run {
                    self.isInstallingProfessionalModels = false
                    self.refreshProfessionalPipelineStatus()
                    self.statusText = "Error instalando recursos internos: \(error.localizedDescription)"
                }
            }
        }
    }

    func installBundledProfessionalModelsOnLaunch() {
        guard !isInstallingProfessionalModels else { return }
        isInstallingProfessionalModels = true
        Task {
            do {
                _ = try await professionalModelInstaller.installAvailableModels()
                await MainActor.run {
                    self.isInstallingProfessionalModels = false
                    self.refreshProfessionalPipelineStatus()
                }
            } catch {
                await MainActor.run {
                    self.isInstallingProfessionalModels = false
                    self.refreshProfessionalPipelineStatus()
                }
            }
        }
    }

    func loadBackgroundImage(url: URL) {
        backgroundImageURL = url
        statusText = "Imagen de fondo cargada: \(url.lastPathComponent)"
    }

    func clearBackgroundImage() {
        backgroundImageURL = nil
        statusText = "Imagen de fondo eliminada"
    }

    private func bindPipeline() {
        let faceTracking = container.faceTracking
        let renderer = container.renderer
        let virtualCamera = container.virtualCamera

        container.videoCapture.onFrame = { [weak self] sampleBuffer in
            guard let self else { return }
            guard self.frameProcessingSemaphore.wait(timeout: .now()) == .success else {
                // Evita cola acumulada y latencia visible en gestos.
                return
            }
            faceTracking.process(sampleBuffer: sampleBuffer)

            guard
                let inputBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            else { return }

            self.processingQueue.async {
                defer { self.frameProcessingSemaphore.signal() }
                let landmarksSnapshot = self.stateQueue.sync { self.latestLandmarks }
                guard let output = renderer.render(
                    sourceFrame: inputBuffer,
                    trackingMode: self.selectedMode,
                    blurIntensity: Float(self.blurIntensity),
                    pixelationIntensity: Float(self.pixelationIntensity),
                    backgroundMode: self.backgroundMode,
                    backgroundBlurIntensity: Float(self.backgroundBlurIntensity),
                    backgroundColor: self.backgroundCIColor,
                    backgroundImageURL: self.backgroundImageURL,
                    avatarModel: nil,
                    animatedMesh: nil,
                    landmarks: landmarksSnapshot
                ) else { return }

                let time = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
                virtualCamera.send(output, presentationTime: time)
                self.publishPreviewIfNeeded(pixelBuffer: output)
            }
        }

        container.faceTracking.onLandmarks = { [weak self] landmarks in
            guard let self else { return }
            self.stateQueue.async {
                self.latestLandmarks = landmarks
            }
            DispatchQueue.main.async {
                self.isTrackingActive = !landmarks.isEmpty
                if landmarks.isEmpty {
                    self.debugTrackingText = "no faces"
                    return
                }

                let summary = landmarks.enumerated().map { index, face in
                    String(format: "face%d conf %.2f", index + 1, face.expressionConfidence)
                }.joined(separator: " | ")
                self.debugTrackingText = "\(landmarks.count) faces: \(summary)"
            }
        }
    }

    private func publishPreviewIfNeeded(pixelBuffer: CVPixelBuffer) {
        frameCounter += 1
        if frameCounter % 2 != 0 { return }
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        guard let cgImage = previewContext.createCGImage(ciImage, from: ciImage.extent) else { return }
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: ciImage.extent.width, height: ciImage.extent.height))
        DispatchQueue.main.async {
            self.previewImage = nsImage
            self.debugPerformanceText = "blur \(Int(self.blurIntensity)) | pixel \(Int(self.pixelationIntensity)) | fondo \(self.backgroundMode.displayName) | \(self.container.professionalFacePipeline.trackingBackendDescription())"
        }
    }

    private var backgroundCIColor: CIColor {
        switch backgroundColorPreset {
        case .dark:
            return CIColor(red: 0.11, green: 0.12, blue: 0.14, alpha: 1.0)
        case .blue:
            return CIColor(red: 0.17, green: 0.31, blue: 0.57, alpha: 1.0)
        case .green:
            return CIColor(red: 0.15, green: 0.40, blue: 0.30, alpha: 1.0)
        case .purple:
            return CIColor(red: 0.34, green: 0.21, blue: 0.52, alpha: 1.0)
        }
    }

    private func openSystemSettingsURL(_ value: String) {
        guard let url = URL(string: value) else { return }
        NSWorkspace.shared.open(url)
    }
}
