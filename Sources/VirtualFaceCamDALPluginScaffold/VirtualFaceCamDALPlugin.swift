import CoreMedia
import CoreVideo
import Foundation

/// Scaffold del plugin DAL.
/// Implementacion real:
/// - CMIO hardware plug-in interfaces
/// - Registro del dispositivo virtual
/// - Stream provider para CVPixelBuffer -> CMSampleBuffer
public final class VirtualFaceCamDALPluginScaffold {
    private let sharedReader = SharedFrameReader()

    public init() {}

    public func registerVirtualDevice() {
        // TODO: implementar en el paso de integracion CoreMediaIO.
    }

    public func unregisterVirtualDevice() {
        // TODO: implementar.
    }

    public func dequeueFrameForStream() -> (buffer: CVPixelBuffer, time: CMTime)? {
        DALFrameBridge.shared.pullLatestFrame()
    }

    public func latestSharedFrameMetadata() -> (width: Int, height: Int, bytesPerRow: Int, time: CMTime)? {
        sharedReader.readHeaderOnly()
    }
}
