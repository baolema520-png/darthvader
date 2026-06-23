import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var viewModel: AppViewModel

    var body: some View {
        HStack(spacing: 16) {
            PreviewView(
                isCameraActive: viewModel.isCameraActive,
                previewImage: viewModel.previewImage,
                statusText: viewModel.statusText,
                debugTrackingText: viewModel.debugTrackingText,
                debugPerformanceText: viewModel.debugPerformanceText,
                showDebugOverlay: viewModel.isDebugModeEnabled
            )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            ControlPanelView(
                mode: $viewModel.selectedMode,
                blurIntensity: $viewModel.blurIntensity,
                pixelationIntensity: $viewModel.pixelationIntensity,
                backgroundMode: $viewModel.backgroundMode,
                backgroundBlurIntensity: $viewModel.backgroundBlurIntensity,
                backgroundColorPreset: $viewModel.backgroundColorPreset,
                isDebugModeEnabled: $viewModel.isDebugModeEnabled,
                isCameraActive: viewModel.isCameraActive,
                isTrackingActive: viewModel.isTrackingActive,
                isDALInstalled: viewModel.isDALInstalled,
                statusText: viewModel.statusText,
                dalStatusText: viewModel.dalStatusText,
                extensionStatusText: viewModel.extensionStatusText,
                professionalPipelineText: viewModel.professionalPipelineText,
                isInstallingDAL: viewModel.isInstallingDAL,
                isActivatingExtension: viewModel.isActivatingExtension,
                isInstallingProfessionalModels: viewModel.isInstallingProfessionalModels,
                onStart: { viewModel.start() },
                onStop: { viewModel.stop() },
                onToggleVirtualCamera: { viewModel.toggleVirtualCamera() },
                onRefreshDALStatus: { viewModel.refreshDALStatus() },
                onAutoInstallDAL: { viewModel.installDALAutomatically() },
                onInstallProfessionalModels: { viewModel.installProfessionalModels() },
                onActivateExtension: { viewModel.activateCameraExtension() },
                onOpenSetupGuide: { viewModel.openSetupGuide() },
                hasBackgroundImage: viewModel.backgroundImageURL != nil,
                onPickBackgroundImage: { pickBackgroundImage() },
                onClearBackgroundImage: { viewModel.clearBackgroundImage() }
            )
            .frame(width: 330)
        }
        .padding(16)
        .alert("Instala 520CAM en Aplicaciones", isPresented: $viewModel.showInstallLocationWarning) {
            Button("Abrir Aplicaciones") {
                viewModel.openApplicationsFolder()
            }
            Button("Entendido", role: .cancel) {}
        } message: {
            Text("La cámara virtual solo funciona si 520CAM está en la carpeta Aplicaciones. Arrástrala desde el DMG o cierra esta copia y abre la instalada.")
        }
    }

    private func pickBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .bmp]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        if panel.runModal() == .OK, let url = panel.url {
            viewModel.loadBackgroundImage(url: url)
        }
    }
}
