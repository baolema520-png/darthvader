import CoreMedia
import CoreVideo
import Foundation
import OSLog

final class SharedFrameReader {
    private static let headerSize = 36
    private static let frameMagic: UInt32 = 0x5646434D
    private let groupFileURL: URL?
    private let sharedFileURL = URL(fileURLWithPath: "/Users/Shared/VirtualFaceCam/virtualfacecam_frame.bin")
    private let varTmpFileURL = URL(fileURLWithPath: "/var/tmp/virtualfacecam_frame.bin")
    private let tmpFileURL = URL(fileURLWithPath: "/tmp/virtualfacecam_frame.bin")
    private var generatedFrameIndex: Int64 = 0
    private let logger = Logger(subsystem: "com.virtualfacecam.app.cameraextension", category: "SharedFrameReader")
    private var decodedFrameCount: Int = 0
    private var fallbackFrameCount: Int = 0
    private var decodeRejectCount: Int = 0

    init() {
        groupFileURL = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.virtualfacecam.shared")?
            .appendingPathComponent("virtualfacecam_frame.bin")
        let resolvedGroup = String(describing: groupFileURL)
        let resolvedShared = sharedFileURL.path
        let resolvedVarTmp = varTmpFileURL.path
        let resolvedTmp = tmpFileURL.path
        logger.info("Init groupFileURL=\(resolvedGroup, privacy: .public) sharedFileURL=\(resolvedShared, privacy: .public) varTmpFileURL=\(resolvedVarTmp, privacy: .public) tmpFileURL=\(resolvedTmp, privacy: .public)")
    }

    func readSampleBuffer() -> CMSampleBuffer? {
        for sourceURL in orderedSourceURLs() {
            guard
                let data = try? Data(contentsOf: sourceURL),
                data.count > Self.headerSize
            else {
                decodeRejectCount += 1
                if decodeRejectCount.isMultiple(of: 60) {
                    logger.error("Read reject path=\(sourceURL.path, privacy: .public) count=\(self.decodeRejectCount, privacy: .public)")
                }
                continue
            }
            if let sampleBuffer = decodeSampleBuffer(from: data) {
                decodedFrameCount += 1
                if decodedFrameCount.isMultiple(of: 60) {
                    logger.info("Decoded frames=\(self.decodedFrameCount, privacy: .public) fallback=\(self.fallbackFrameCount, privacy: .public)")
                }
                return sampleBuffer
            }
            decodeRejectCount += 1
            if decodeRejectCount.isMultiple(of: 60) {
                logger.error("Decode reject path=\(sourceURL.path, privacy: .public) size=\(data.count, privacy: .public) count=\(self.decodeRejectCount, privacy: .public)")
            }
        }
        fallbackFrameCount += 1
        if fallbackFrameCount.isMultiple(of: 60) {
            let fm = FileManager.default
            let groupPath = groupFileURL?.path ?? "<nil>"
            let groupExists = groupFileURL.map { fm.fileExists(atPath: $0.path) } ?? false
            let sharedExists = fm.fileExists(atPath: sharedFileURL.path)
            let varTmpExists = fm.fileExists(atPath: varTmpFileURL.path)
            let tmpExists = fm.fileExists(atPath: tmpFileURL.path)
            logger.error(
                """
                Fallback frames=\(self.fallbackFrameCount, privacy: .public) decoded=\(self.decodedFrameCount, privacy: .public) \
                groupPath=\(groupPath, privacy: .public) groupExists=\(groupExists, privacy: .public) \
                sharedPath=\(self.sharedFileURL.path, privacy: .public) sharedExists=\(sharedExists, privacy: .public) \
                varTmpPath=\(self.varTmpFileURL.path, privacy: .public) varTmpExists=\(varTmpExists, privacy: .public) \
                tmpPath=\(self.tmpFileURL.path, privacy: .public) tmpExists=\(tmpExists, privacy: .public)
                """
            )
            logger.error("Fallback frames=\(self.fallbackFrameCount, privacy: .public) decoded=\(self.decodedFrameCount, privacy: .public)")
        }
        return nil
    }

    private func orderedSourceURLs() -> [URL] {
        let fileManager = FileManager.default
        let candidates = [groupFileURL, sharedFileURL, varTmpFileURL, tmpFileURL].compactMap { $0 }
        let existing = candidates.compactMap { url -> (URL, Date)? in
            guard
                fileManager.fileExists(atPath: url.path),
                let attrs = try? fileManager.attributesOfItem(atPath: url.path),
                let modified = attrs[.modificationDate] as? Date
            else { return nil }
            return (url, modified)
        }
        return existing.sorted(by: { $0.1 > $1.1 }).map(\.0)
    }

    private func decodeSampleBuffer(from data: Data) -> CMSampleBuffer? {
        guard
            let magic = data.readUInt32(at: 0),
            let width = data.readUInt32(at: 4),
            let height = data.readUInt32(at: 8),
            let bytesPerRow = data.readUInt32(at: 12),
            let format = data.readUInt32(at: 16)
        else {
            return nil
        }
        guard magic == Self.frameMagic, format == kCVPixelFormatType_32BGRA else {
            return nil
        }

        let payload = data.dropFirst(Self.headerSize)
        let expectedSize = Int(bytesPerRow * height)
        guard payload.count >= expectedSize else {
            return nil
        }

        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: Int(width),
            kCVPixelBufferHeightKey as String: Int(height),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(width),
            Int(height),
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let dstBase = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let dstBytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        payload.withUnsafeBytes { src in
            guard let srcBase = src.baseAddress else { return }
            for row in 0..<Int(height) {
                let srcPtr = srcBase.advanced(by: row * Int(bytesPerRow))
                let dstPtr = dstBase.advanced(by: row * dstBytesPerRow)
                memcpy(dstPtr, srcPtr, min(dstBytesPerRow, Int(bytesPerRow)))
            }
        }

        var formatDescription: CMFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else { return nil }

        let frameDuration = CMTime(value: 1, timescale: 30)
        let presentationTime = CMTime(value: generatedFrameIndex, timescale: 30)
        generatedFrameIndex += 1
        var timing = CMSampleTimingInfo(
            duration: frameDuration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr else { return nil }
        return sampleBuffer
    }

    private func makeFallbackSampleBuffer() -> CMSampleBuffer? {
        let width = 1280
        let height = 720
        var pixelBuffer: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ]
        guard CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        ) == kCVReturnSuccess, let pixelBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
            let t = UInt8(generatedFrameIndex % 255)
            for y in 0..<height {
                let row = baseAddress.advanced(by: y * bytesPerRow)
                let ptr = row.assumingMemoryBound(to: UInt8.self)
                for x in 0..<width {
                    let i = x * 4
                    ptr[i + 0] = UInt8((x + Int(t)) % 255) // B
                    ptr[i + 1] = UInt8((y + Int(t)) % 255) // G
                    ptr[i + 2] = UInt8(255 - t)            // R
                    ptr[i + 3] = 255                       // A
                }
            }
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var formatDescription: CMFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else {
            return nil
        }

        let frameDuration = CMTime(value: 1, timescale: 30)
        let presentationTime = CMTime(value: generatedFrameIndex, timescale: 30)
        generatedFrameIndex += 1
        var timing = CMSampleTimingInfo(
            duration: frameDuration,
            presentationTimeStamp: presentationTime,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr else {
            return nil
        }
        return sampleBuffer
    }
}

private extension Data {
    func readUInt32(at offset: Int) -> UInt32? {
        guard count >= offset + 4 else { return nil }
        return subdata(in: offset..<(offset + 4)).withUnsafeBytes { raw in
            raw.load(as: UInt32.self).littleEndian
        }
    }
}
