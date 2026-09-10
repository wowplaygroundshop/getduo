import AppKit
import Metal
import QuartzCore

extension NSScreen {
    var displayID: CGDirectDisplayID {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? CGMainDisplayID()
    }

    /// The lid only belongs to the built-in panel, so that is the only screen we fold.
    static var builtIn: NSScreen? {
        screens.first { CGDisplayIsBuiltin($0.displayID) != 0 } ?? screens.first
    }
}

/// A click-through, all-spaces window sitting above everything, filled with one Metal layer.
final class OverlayController {
    private let renderer: FoldRenderer
    private let view: MetalView
    private let panel: NSPanel
    private var link: CADisplayLink?

    /// Returns the texture and parameters for this frame, or nil to skip drawing.
    var frame: (() -> (MTLTexture, FoldParams)?)?

    var isVisible: Bool { panel.isVisible }

    init(renderer: FoldRenderer) {
        self.renderer = renderer
        self.view = MetalView(device: renderer.device)

        panel = NSPanel(contentRect: .zero,
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.contentView = view
        panel.level = .screenSaver
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.isOpaque = true
        panel.backgroundColor = .black
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.sharingType = .readOnly
        panel.animationBehavior = .none
    }

    /// Sizes the panel and starts the render loop. The panel itself stays hidden
    /// until the first frame is actually drawn, so there is never a black flash.
    func show() {
        guard let screen = NSScreen.builtIn, link == nil else { return }
        panel.setFrame(screen.frame, display: false)
        let scale = screen.backingScaleFactor
        view.metalLayer.contentsScale = scale
        view.metalLayer.drawableSize = CGSize(width: screen.frame.width * scale,
                                              height: screen.frame.height * scale)
        let link = screen.displayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func hide() {
        link?.invalidate()
        link = nil
        panel.orderOut(nil)
    }

    @objc private func tick() {
        guard let (texture, params) = frame?() else { return }
        renderer.render(texture, to: view.metalLayer, params: params)
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}
