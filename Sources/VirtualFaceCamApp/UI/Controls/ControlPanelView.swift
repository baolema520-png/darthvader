import SwiftUI

struct ControlPanelView: View {
    @Binding var mode: TrackingMode
    @Binding var blurIntensity: Double
    @Binding var pixelationIntensity: Double
    @Binding var backgroundMode: VirtualBackgroundMode
    @Binding var backgroundBlurIntensity: Double
    @Binding var backgroundColorPreset: VirtualBackgroundColorPreset
    @Binding var isDebugModeEnabled: Bool

    let isCameraActive: Bool
    let isTrackingActive: Bool
    let isDALInstalled: Bool
    let statusText: String
    let dalStatusText: String
    let extensionStatusText: String
    let professionalPipelineText: String
    let isInstallingDAL: Bool
    let isActivatingExtension: Bool
    let isInstallingProfessionalModels: Bool
    let onStart: () -> Void
    let onStop: () -> Void
    let onToggleVirtualCamera: () -> Void
    let onRefreshDALStatus: () -> Void
    let onAutoInstallDAL: () -> Void
    let onInstallProfessionalModels: () -> Void
    let onActivateExtension: () -> Void
    let onOpenSetupGuide: () -> Void
    let hasBackgroundImage: Bool
    let onPickBackgroundImage: () -> Void
    let onClearBackgroundImage: () -> Void
    @State private var showAdvancedButtons = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("520CAM")
                    .font(.title2.bold())

                Picker("Mode", selection: $mode) {
                    Text("Cara turbia").tag(TrackingMode.blur)
                    Text("Pixelar").tag(TrackingMode.pixelate)
                }
                .pickerStyle(.segmented)

                Group {
                    Text("Intensidad blur: \(Int(blurIntensity))")
                    Slider(value: $blurIntensity, in: 2...30, step: 1)
                    Text("Intensidad pixelado: \(Int(pixelationIntensity))")
                    Slider(value: $pixelationIntensity, in: 4...45, step: 1)
                }

                Divider()

                Group {
                    Text("Fondo virtual")
                        .font(.headline)

                    Picker("Tipo de fondo", selection: $backgroundMode) {
                        ForEach(VirtualBackgroundMode.allCases) { option in
                            Text(option.displayName).tag(option)
                        }
                    }
                    .pickerStyle(.menu)

                    if backgroundMode == .blur {
                        Text("Intensidad fondo turbio: \(Int(backgroundBlurIntensity))")
                        Slider(value: $backgroundBlurIntensity, in: 6...40, step: 1)
                    }

                    if backgroundMode == .solidColor {
                        Picker("Color de fondo", selection: $backgroundColorPreset) {
                            ForEach(VirtualBackgroundColorPreset.allCases) { option in
                                Text(option.displayName).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if backgroundMode == .image {
                        HStack {
                            Button("Elegir imagen de fondo", action: onPickBackgroundImage)
                            if hasBackgroundImage {
                                Button("Quitar imagen", action: onClearBackgroundImage)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                HStack {
                    Circle()
                        .fill(isCameraActive ? .green : .red)
                        .frame(width: 9, height: 9)
                    Text("Camera")
                    Circle()
                        .fill(isTrackingActive ? .green : .orange)
                        .frame(width: 9, height: 9)
                    Text("Tracking")
                    Circle()
                        .fill(isDALInstalled ? .green : .red)
                        .frame(width: 9, height: 9)
                    Text("DAL")
                }
                .font(.caption)

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(dalStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(extensionStatusText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text(professionalPipelineText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Button("Start", action: onStart)
                        Button("Stop", action: onStop)
                        Button("Virtual Cam", action: onToggleVirtualCamera)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(showAdvancedButtons ? "Ocultar botones avanzados" : "Mostrar botones avanzados") {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showAdvancedButtons.toggle()
                        }
                    }
                    .buttonStyle(.bordered)

                    if showAdvancedButtons {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Modo debug", isOn: $isDebugModeEnabled)
                                .toggleStyle(.switch)

                            HStack {
                                Button(isInstallingDAL ? "Installing..." : "Auto Install DAL", action: onAutoInstallDAL)
                                    .disabled(isInstallingDAL)
                                Button("Refresh DAL status", action: onRefreshDALStatus)
                            }

                            Button(
                                isInstallingProfessionalModels ? "Instalando recursos internos..." : "Reinstalar recursos internos",
                                action: onInstallProfessionalModels
                            )
                            .disabled(isInstallingProfessionalModels)
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Button(isActivatingExtension ? "Activating extension..." : "Activate Camera Extension", action: onActivateExtension)
                                .disabled(isActivatingExtension)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.borderedProminent)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    Button("Ayuda de configuración", action: onOpenSetupGuide)
                        .buttonStyle(.bordered)
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .scrollIndicators(.visible)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }
}
