import CoreMedia
import CoreVideo
import Foundation

public final class SharedFrameReader {
    public init() {}

    public func readHeaderOnly() -> (width: Int, height: Int, bytesPerRow: Int, time: CMTime)? {
        let url = URL(fileURLWithPath: "/tmp/virtualfacecam_frame.bin")
        guard let data = try? Data(contentsOf: url), data.count >= MemoryLayout<FrameHeader>.size else {
            return nil
        }

        return data.withUnsafeBytes { rawBuffer in
            guard let header = rawBuffer.baseAddress?.assumingMemoryBound(to: FrameHeader.self) else {
                return nil
            }
            guard header.pointee.magic == 0x5646434D else { return nil }
            return (
                width: Int(header.pointee.width),
                height: Int(header.pointee.height),
                bytesPerRow: Int(header.pointee.bytesPerRow),
                time: CMTime(value: header.pointee.timeValue, timescale: header.pointee.timeScale)
            )
        }
    }
}

private struct FrameHeader {
    var magic: UInt32
    var width: UInt32
    var height: UInt32
    var bytesPerRow: UInt32
    var format: UInt32
    var timeValue: Int64
    var timeScale: Int32
}
