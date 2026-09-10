import SwiftUI
import MetalKit

/// The same shader, run over the user's wallpaper, so settings can be judged without
/// moving the lid. Renders on demand rather than on a display link.
struct FoldPreview: NSViewRepresentable {
    var preset: Preset
    var amount: Double

    final class Coordinator {
        let renderer = FoldRenderer()
        var texture: MTLTexture?

        init() {
            guard let renderer else { return }
            texture = Coordinator.wallpaperTexture(renderer.device) ?? Coordinator.fallback(renderer.device)
        }

        static func wallpaperTexture(_ device: MTLDevice) -> MTLTexture? {
            guard let screen = NSScreen.main,
                  let url = NSWorkspace.shared.desktopImageURL(for: screen) else { return nil }
            return try? MTKTextureLoader(device: device).newTexture(
                URL: url, options: [.SRGB: false, .textureUsage: NSNumber(value: MTLTextureUsage.shaderRead.rawValue)])
        }

        static func fallback(_ device: MTLDevice) -> MTLTexture? {
            let w = 640, h = 400
            let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: w, height: h, mipmapped: false)
            guard let tex = device.makeTexture(descriptor: desc) else { return nil }
            var px = [UInt8](repeating: 0, count: w * h * 4)
            for y in 0..<h {
                for x in 0..<w {
                    let i = (y * w + x) * 4
                    let t = Double(y) / Double(h)
                    px[i] = UInt8(40 + 90 * t)          // B
                    px[i + 1] = UInt8(24 + 40 * t)      // G
                    px[i + 2] = UInt8(70 + 120 * (1 - t)) // R
                    px[i + 3] = 255
                }
            }
            tex.replace(region: MTLRegionMake2D(0, 0, w, h), mipmapLevel: 0, withBytes: px, bytesPerRow: w * 4)
            return tex
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> MetalView {
        let device = context.coordinator.renderer?.device ?? MTLCreateSystemDefaultDevice()!
        let view = MetalView(device: device)
        view.metalLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2
        return view
    }

    func updateNSView(_ view: MetalView, context: Context) {
        let draw = { [preset, amount] in
            guard let renderer = context.coordinator.renderer,
                  let texture = context.coordinator.texture,
                  view.metalLayer.drawableSize.width > 0 else { return }
            renderer.render(texture, to: view.metalLayer,
                            params: FoldParams(preset: preset, amount: Float(amount)))
        }
        view.onLayout = draw
        draw()
    }
}
