import CoreMedia
import CoreVideo
import Foundation
import OSLog

final class SharedFrameWriter {
    private static let headerSize = 36
    private static let frameMagic: UInt32 = 0x5646434D
    private let targetFileURLs: [URL]
    private var fallbackFrameIndex: Int64 = 0
    private let fallbackTimescale: Int32 = 30
    private let logger = Logger(subsystem: "com.virtualfacecam.app", category: "SharedFrameWriter")
    private var writeCount: Int = 0

    init() {
        var urls: [URL] = [URL(fileURLWithPath: "/Users/Shared/VirtualFaceCam/virtualfacecam_frame.bin"),
                           URL(fileURLWithPath: "/var/tmp/virtualfacecam_frame.bin"),
                           URL(fileURLWithPath: "/tmp/virtualfacecam_frame.bin")]
        if
            let groupURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.virtualfacecam.shared"
            )
        {
            urls.insert(groupURL.appendingPathComponent("virtualfacecam_frame.bin"), at: 0)
        }
        targetFileURLs = urls
    }

    func write(pixelBuffer: CVPixelBuffer, time: CMTime) {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let payloadSize = bytesPerRow * height

        let validTime = sanitizedPresentationTime(from: time)
        var blob = Data(capacity: Self.headerSize + payloadSize)
        blob.appendUInt32(Self.frameMagic)
        blob.appendUInt32(UInt32(width))
        blob.appendUInt32(UInt32(height))
        blob.appendUInt32(UInt32(bytesPerRow))
        blob.appendUInt32(UInt32(kCVPixelFormatType_32BGRA))
        blob.appendInt64(validTime.value)
        blob.appendInt32(Int32(validTime.timescale))
        blob.appendInt32(0) // reservado para alineacion/version futura
        blob.append(Data(bytes: base, count: payloadSize))

        for fileURL in targetFileURLs {
            do {
                let parent = fileURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                try blob.write(to: fileURL, options: .atomic)
                writeCount += 1
                if writeCount.isMultiple(of: 120) {
                    logger.info("Wrote frames=\(self.writeCount, privacy: .public) path=\(fileURL.path, privacy: .public)")
                }
            } catch {
                // Best effort: si falla un destino, se intenta el siguiente.
                logger.error("Write failed path=\(fileURL.path, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private func sanitizedPresentationTime(from time: CMTime) -> CMTime {
        if CMTIME_IS_VALID(time), time.timescale > 0, time.value >= 0 {
            return time
        }
        let fallback = CMTime(value: fallbackFrameIndex, timescale: fallbackTimescale)
        fallbackFrameIndex += 1
        return fallback
    }
}

private extension Data {
    mutating func appendUInt32(_ value: UInt32) {
        var le = value.littleEndian
        append(UnsafeBufferPointer(start: &le, count: 1))
    }

    mutating func appendInt32(_ value: Int32) {
        var le = value.littleEndian
        append(UnsafeBufferPointer(start: &le, count: 1))
    }

    mutating func appendInt64(_ value: Int64) {
        var le = value.littleEndian
        append(UnsafeBufferPointer(start: &le, count: 1))
    }
}
