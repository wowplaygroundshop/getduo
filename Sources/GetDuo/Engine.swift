import AppKit
import Combine
import Metal

@MainActor
final class FoldEngine: ObservableObject {
    static let shared = FoldEngine()

    @Published private(set) var angle: Double = 180
    @Published private(set) var amount: Double = 0
    @Published private(set) var sensorAvailable = false
    @Published private(set) var hasPermission = CGPreflightScreenCaptureAccess()
    @Published var paused = false { didSet { sync() } }

    /// When set, the sensor is ignored. Used by the settings preview.
    @Published var manualAngle: Double? { didSet { sync() } }

    let settings = FoldSettings.shared
    private let sensor = LidAngleSensor()
    private var renderer: FoldRenderer?
    private var capture: ScreenCapture?
    private var overlay: OverlayController?

    private var target: Double = 0
    private var velocity: Double = 0
    private var lastTick: CFTimeInterval = 0
    private var starving = 0
    private var ticks = 0
    private var lastFrames = 0
    private var lastReport: CFTimeInterval = 0
    private var bag = Set<AnyCancellable>()

    private init() {
        manualAngle = nil
    }

    /// Set GETDUO_DEBUG=1 to trace activation. Errors always log.
    private static let debug = ProcessInfo.processInfo.environment["GETDUO_DEBUG"] != nil
    func log(_ message: String) { if Self.debug { NSLog("GetDuo: %@", message) } }

    func start() {
        guard let renderer = FoldRenderer() else {
            NSLog("GetDuo: Metal pipeline unavailable")
            return
        }
        self.renderer = renderer
        let capture = ScreenCapture(device: renderer.device)
        let overlay = OverlayController(renderer: renderer)
        overlay.frame = { [weak self] in self?.nextFrame() }
        self.capture = capture
        self.overlay = overlay

        sensor.start()
        sensorAvailable = sensor.isAvailable
        angle = sensor.angle

        // The hinge is polled on its own thread; this is what notices the lid starting to
        // move while the overlay (and its display link) is not running yet.
        Timer.scheduledTimer(withTimeInterval: 1.0 / 12, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let degrees = self.sensor.angle
                if degrees != self.angle { self.angle = degrees }
                self.sync()
            }
        }

        for publisher in [settings.$enabled.map { _ in () }.eraseToAnyPublisher(),
                          settings.$intensity.map { _ in () }.eraseToAnyPublisher(),
                          settings.$clearAngle.map { _ in () }.eraseToAnyPublisher(),
                          settings.$fullAngle.map { _ in () }.eraseToAnyPublisher()] {
            publisher.sink { [weak self] in self?.sync() }.store(in: &bag)
        }
        // The grant can land while we are running, and preflight is the only way to hear about it.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPermission() }
        }
        sync()
    }

    var effectiveAngle: Double { manualAngle ?? sensor.angle }

    /// Runs the effect for a couple of seconds without touching the lid, for demos
    /// and for anyone who wants to see what they just bought.
    func demo(seconds: Double = 2.5) {
        manualAngle = settings.fullAngle
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            manualAngle = nil
        }
    }

    /// The system prompt only ever appears once per binary. After that the only way
    /// through is the Screen Recording pane, so fall back to opening it.
    func requestPermission() {
        CGRequestScreenCaptureAccess()
        refreshPermission()
        guard !hasPermission else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            self.refreshPermission()
            guard !self.hasPermission else { return }
            NSWorkspace.shared.open(URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    func refreshPermission() {
        let now = CGPreflightScreenCaptureAccess()
        if now != hasPermission {
            hasPermission = now
            sync()
        }
    }

    /// ScreenCaptureKit only picks up a fresh grant after a relaunch.
    func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - Activation

    private func sync() {
        // A demo runs even when the effect is switched off, so the menu item always shows something.
        let live = (settings.enabled || manualAngle != nil) && !paused
        target = live ? settings.amount(forAngle: effectiveAngle) : 0
        log("sync angle=\(effectiveAngle) target=\(target) perm=\(hasPermission)")
        // Poll fast while anything is on screen, and while the lid is near the trigger.
        sensor.isEngaged = target > 0 || amount > 0.001 || effectiveAngle < settings.clearAngle + 20
        if target > 0 || amount > 0.001 { activate() }
    }

    private func activate() {
        guard let capture, let overlay else { return log("activate: no engine") }
        guard hasPermission else { return log("activate: no screen recording permission") }
        overlay.show()
        guard !capture.isRunning else { return }
        Task { [weak self] in
            do {
                    try await capture.start(displayID: NSScreen.builtIn?.displayID ?? CGMainDisplayID())
                self?.log("capture started")
            } catch {
                NSLog("GetDuo: capture failed - \(error)")
                self?.deactivate()
            }
        }
    }

    private func deactivate() {
        overlay?.hide()
        capture?.stop()
        amount = 0
        velocity = 0
        lastTick = 0
    }

    // MARK: - Frame

    /// Critically damped spring on the fold amount. The hinge sensor reports in whole
    /// degrees and only on change, so the spring is what makes the motion continuous.
    private func nextFrame() -> (MTLTexture, FoldParams)? {
        let now = CACurrentMediaTime()
        ticks += 1
        if now - lastReport > 1 {
            log("ticks/s=\(ticks) frames/s=\((capture?.frameCount ?? 0) - lastFrames) amount=\(String(format: "%.3f", amount)) target=\(String(format: "%.3f", target))")
            ticks = 0; lastFrames = capture?.frameCount ?? 0; lastReport = now
        }
        let dt = lastTick == 0 ? 1.0 / 60 : min(now - lastTick, 1.0 / 20)
        lastTick = now

        // Stiff enough to sit on the hand rather than trail it: ~38ms to close the error.
        let k = 700.0
        let c = 2 * k.squareRoot()
        target = (settings.enabled || manualAngle != nil) && !paused
            ? settings.amount(forAngle: effectiveAngle) : 0
        velocity += ((target - amount) * k - c * velocity) * dt
        let previous = amount
        amount += velocity * dt
        if settings.sound, previous > 0.2, amount <= 0.2 { NSSound(named: "Glass")?.play() }

        if target <= 0 && amount < 0.002 {
            deactivate()
            return nil
        }
        amount = min(max(amount, 0), 1.2)

        guard let texture = capture?.latest else {
            if starving == 0 { log("waiting for first captured frame") }
            starving += 1
            return nil
        }
        if starving > 0 { log("first frame after \(starving) empty ticks"); starving = 0 }
        return (texture, FoldParams(preset: settings.preset, amount: Float(amount)))
    }
}
