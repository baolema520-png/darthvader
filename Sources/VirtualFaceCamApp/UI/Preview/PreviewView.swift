import AppKit
import SwiftUI

struct PreviewView: View {
    let isCameraActive: Bool
    let previewImage: NSImage?
    let statusText: String
    let debugTrackingText: String
    let debugPerformanceText: String
    let showDebugOverlay: Bool

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.black.opacity(0.86))
            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(8)
                if isScanning {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.green.opacity(0.9), lineWidth: 3)
                        .padding(30)
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [.clear, .green.opacity(0.65), .clear],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(height: 4)
                        .padding(.horizontal, 44)
                        .frame(maxHeight: .infinity, alignment: .center)
                }
                if showDebugOverlay {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(debugTrackingText)
                        Text(debugPerformanceText)
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white)
                    .padding(8)
                    .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                    .padding(14)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                Text(statusText)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background((isScanning ? Color.green : Color.black).opacity(0.65), in: Capsule())
                    .padding(18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            } else {
                Text(isCameraActive ? "Capturando..." : "Camera not started")
                    .foregroundStyle(.white.opacity(0.9))
                    .font(.headline)
            }
        }
    }

    private var isScanning: Bool {
        let lowered = statusText.lowercased()
        return lowered.contains("calibr") || lowered.contains("creando identidad") || lowered.contains("scan")
    }
}
