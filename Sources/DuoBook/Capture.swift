import Foundation
import ScreenCaptureKit
import Metal
import CoreVideo

/// Streams one display straight into Metal textures. No CPU copy.
final class ScreenCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    private let device: MTLDevice
    private let queue = DispatchQueue(label: "app.askmaddyy.duobook.capture")
    private var stream: SCStream?
    private var starting = false
    private let lock = NSLock()
    private var _latest: MTLTexture?
    private(set) var frameCount = 0

    /// Most recent captured frame, or nil before the first one lands.
    var latest: MTLTexture? {
        lock.lock(); defer { lock.unlock() }
        return _latest
    }

    var isRunning: Bool { stream != nil || starting }

    init(device: MTLDevice) {
        self.device = device
    }

    func start(displayID: CGDirectDisplayID) async throws {
        guard stream == nil, !starting else { return }
        starting = true
        defer { starting = false }

        // onScreenWindowsOnly must be false: our overlay is still hidden when the filter is
        // built, and if our app is missing from this list nothing gets excluded and the
        // overlay captures itself into a black recursive tunnel.
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.noDisplay
        }
        // Excluding our own app is what stops the overlay mirroring itself into infinity.
        let ourselves = content.applications.filter { $0.bundleIdentifier == Bundle.main.bundleIdentifier }
        guard !ourselves.isEmpty else { throw CaptureError.cannotExcludeSelf }
        let filter = SCContentFilter(display: display, excludingApplications: ourselves, exceptingWindows: [])

        let config = SCStreamConfiguration()
        config.width = display.width * scale(displayID)
        config.height = display.height * scale(displayID)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB
        config.minimumFrameInterval = CMTime(value: 1, timescale: 120)
        config.queueDepth = 4
        config.showsCursor = true
        config.capturesAudio = false

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() {
        guard let stream else { return }
        self.stream = nil
        lock.lock(); _latest = nil; lock.unlock()
        Task { try? await stream.stopCapture() }
    }

    private func scale(_ displayID: CGDirectDisplayID) -> Int {
        guard let mode = CGDisplayCopyDisplayMode(displayID), mode.pixelWidth > 0 else { return 2 }
        return max(1, mode.pixelWidth / max(mode.width, 1))
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sb: CMSampleBuffer, of type: SCStreamOutputType) {
        // Idle and blank frames carry a surface with no new content in it. Using one
        // paints the overlay black, so we keep the last complete frame instead.
        guard type == .screen, sb.isValid, isComplete(sb),
              let pixels = CMSampleBufferGetImageBuffer(sb),
              let surface = CVPixelBufferGetIOSurface(pixels)?.takeUnretainedValue()
        else { return }

        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .bgra8Unorm,
            width: CVPixelBufferGetWidth(pixels),
            height: CVPixelBufferGetHeight(pixels),
            mipmapped: false)
        desc.usage = .shaderRead
        desc.storageMode = .shared
        // ponytail: one wrapper texture per frame. Cache by IOSurfaceID only if this ever shows up in a trace.
        guard let texture = device.makeTexture(descriptor: desc, iosurface: surface, plane: 0) else { return }

        lock.lock(); _latest = texture; frameCount += 1; lock.unlock()
    }

    private func isComplete(_ sb: CMSampleBuffer) -> Bool {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(sb, createIfNecessary: false)
                as? [[SCStreamFrameInfo: Any]],
              let raw = attachments.first?[.status] as? Int,
              let status = SCFrameStatus(rawValue: raw)
        else { return false }
        return status == .complete
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        self.stream = nil
    }

    enum CaptureError: Error { case noDisplay, cannotExcludeSelf }
}
