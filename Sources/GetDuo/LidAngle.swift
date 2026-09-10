import Foundation
import IOKit.hid
import QuartzCore

/// Reads the MacBook lid hinge angle over HID.
/// Sensor page 0x20, usage 0x8A. Feature report 1 is three bytes: report id, then the hinge
/// angle in whole degrees as a little-endian Int16.
///
/// The device only *pushes* an input report about once a second, which is nowhere near enough
/// to drive an animation. So we poll the feature report on a dedicated thread instead — a read
/// costs about 1.2 ms and always returns the current angle. Polling runs at display rate while
/// the fold is live and drops to a trickle when the lid is parked, so an open laptop costs
/// nothing.
final class LidAngleSensor {
    static let debug = ProcessInfo.processInfo.environment["GETDUO_DEBUG"] != nil

    private let sensorPage = 0x20
    private let lidUsage = 0x8A
    private let reportID: CFIndex = 1

    private var manager: IOHIDManager?
    private var device: IOHIDDevice?
    private var thread: Thread?

    private let lock = NSLock()
    private var _angle: Double = 180
    private var _engaged = false

    private(set) var isAvailable = false

    /// Latest hinge angle in degrees. Safe to read from any thread, every frame.
    var angle: Double {
        lock.lock(); defer { lock.unlock() }
        return _angle
    }

    /// While engaged we poll at display rate; otherwise we idle.
    var isEngaged: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _engaged }
        set { lock.lock(); _engaged = newValue; lock.unlock() }
    }

    func start() {
        let mgr = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(mgr, [
            kIOHIDPrimaryUsagePageKey: sensorPage,
            kIOHIDPrimaryUsageKey: lidUsage,
        ] as CFDictionary)
        guard IOHIDManagerOpen(mgr, IOOptionBits(kIOHIDOptionsTypeNone)) == kIOReturnSuccess,
              let dev = (IOHIDManagerCopyDevices(mgr) as? Set<IOHIDDevice>)?.first
        else { return }

        manager = mgr
        device = dev
        isAvailable = true
        read()

        let thread = Thread { [weak self] in self?.poll() }
        thread.name = "shop.wowplayground.getduo.hinge"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.thread = thread
    }

    func stop() {
        thread?.cancel()
        thread = nil
    }

    private func poll() {
        var last = Double.nan
        var lastChange = CACurrentMediaTime()
        while !(Thread.current.isCancelled) {
            let engaged = isEngaged
            if let degrees = read() {
                if degrees != last {
                    if Self.debug {
                        let now = CACurrentMediaTime()
                        NSLog("GetDuo: hinge %.0f deg  %.0f ms since last change", degrees, (now - lastChange) * 1000)
                        lastChange = now
                    }
                    last = degrees
                }
            }
            // 120 Hz while folding, 12 Hz when parked. The idle rate still catches the
            // moment the lid starts to move, within a frame or two.
            usleep(engaged ? 7_000 : 80_000)
        }
    }

    @discardableResult
    private func read() -> Double? {
        guard let device else { return nil }
        var buffer = [UInt8](repeating: 0, count: 8)
        var length = buffer.count
        guard IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, reportID, &buffer, &length) == kIOReturnSuccess,
              length >= 3, buffer[0] == UInt8(reportID)
        else { return nil }

        let degrees = Double(Int16(bitPattern: UInt16(buffer[1]) | UInt16(buffer[2]) << 8))
        guard degrees > 0, degrees <= 180 else { return nil }
        lock.lock(); _angle = degrees; lock.unlock()
        return degrees
    }
}
