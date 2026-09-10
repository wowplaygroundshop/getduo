import AppKit
import Metal
import QuartzCore
import simd

/// Mirrors `Params` in Shader.metal. Lengths are in canvas units (the shader works on a
/// virtual canvas 1000 units tall), which is what lets the iOS tuning carry over unchanged.
struct FoldParams {
    var resolution: SIMD2<Float> = .zero
    var tilt: Float = 0
    var eyeDistance: Float = 2254
    var blurSpread: Float = 0.12
    var darkening: Float = 0.015
    var baseSeparation: Float = 12

    init() {}
    init(preset: Preset, amount: Float) {
        tilt = amount * preset.maxTilt
        eyeDistance = preset.eyeDistance
        blurSpread = preset.blurSpread
        darkening = preset.darkening
        baseSeparation = preset.baseSeparation
    }
}

/// Ray-casts the captured desktop through a hinged pane of glass.
final class FoldRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState

    init?(device: MTLDevice = MTLCreateSystemDefaultDevice()!) {
        guard let queue = device.makeCommandQueue(),
              let library = try? device.makeDefaultLibrary(bundle: .main),
              let vs = library.makeFunction(name: "foldVertex"),
              let fs = library.makeFunction(name: "foldFragment")
        else { return nil }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vs
        desc.fragmentFunction = fs
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm
        guard let state = try? device.makeRenderPipelineState(descriptor: desc) else { return nil }

        self.device = device
        self.queue = queue
        self.pipeline = state
    }

    func render(_ source: MTLTexture, to layer: CAMetalLayer, params: FoldParams) {
        guard let drawable = layer.nextDrawable(),
              let buffer = queue.makeCommandBuffer() else { return }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .dontCare
        pass.colorAttachments[0].storeAction = .store

        var p = params
        p.resolution = SIMD2(Float(drawable.texture.width), Float(drawable.texture.height))

        if let encoder = buffer.makeRenderCommandEncoder(descriptor: pass) {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentTexture(source, index: 0)
            encoder.setFragmentBytes(&p, length: MemoryLayout<FoldParams>.stride, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            encoder.endEncoding()
        }
        buffer.present(drawable)
        buffer.commit()
    }
}

/// NSView backed directly by a CAMetalLayer.
final class MetalView: NSView {
    override func makeBackingLayer() -> CALayer {
        let layer = CAMetalLayer()
        layer.pixelFormat = .bgra8Unorm
        layer.framebufferOnly = true
        layer.isOpaque = true
        return layer
    }

    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }

    /// Called after the drawable is resized, so on-demand renderers can redraw.
    var onLayout: (() -> Void)?

    init(device: MTLDevice) {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        metalLayer.device = device
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        metalLayer.contentsScale = scale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
    }

    override func layout() {
        super.layout()
        let scale = metalLayer.contentsScale
        metalLayer.drawableSize = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        onLayout?()
    }
}
