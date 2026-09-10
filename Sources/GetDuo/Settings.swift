import Foundation
import Combine

struct Preset: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String
    let symbol: String
    var eyeDistance: Float
    var blurSpread: Float
    var darkening: Float
    var baseSeparation: Float
    var maxTilt: Float

    /// Default presets configure the tilt and glass gap for different visual effects.
    static let all: [Preset] = [
        Preset(id: "silk", name: "Silk", detail: "A soft lean. Barely there.",
               symbol: "wind", eyeDistance: 2254, blurSpread: 0.10,
               darkening: 0.011, baseSeparation: 8, maxTilt: 0.30),
        Preset(id: "shade", name: "Shade", detail: "The balanced fold.",
               symbol: "circle.lefthalf.filled", eyeDistance: 2254, blurSpread: 0.12,
               darkening: 0.015, baseSeparation: 12, maxTilt: 0.45),
        Preset(id: "frost", name: "Frost", detail: "Deep glass. Heavy bloom.",
               symbol: "snowflake", eyeDistance: 2000, blurSpread: 0.16,
               darkening: 0.019, baseSeparation: 18, maxTilt: 0.65),
    ]

    static func named(_ id: String) -> Preset { all.first { $0.id == id } ?? all[1] }
}

final class FoldSettings: ObservableObject {
    static let shared = FoldSettings()

    @Published var enabled: Bool { didSet { d.set(enabled, forKey: "enabled") } }
    @Published var presetID: String { didSet { d.set(presetID, forKey: "presetID") } }
    @Published var intensity: Double { didSet { d.set(intensity, forKey: "intensity") } }
    @Published var clearAngle: Double { didSet { d.set(clearAngle, forKey: "clearAngle") } }
    @Published var fullAngle: Double { didSet { d.set(fullAngle, forKey: "fullAngle") } }
    @Published var sound: Bool { didSet { d.set(sound, forKey: "sound") } }

    var preset: Preset { .named(presetID) }

    private let d = UserDefaults.standard

    private init() {
        d.register(defaults: [
            "enabled": true, "presetID": "shade", "intensity": 1.0,
            "clearAngle": 100.0, "fullAngle": 35.0, "sound": true,
        ])
        enabled = d.bool(forKey: "enabled")
        presetID = d.string(forKey: "presetID") ?? "shade"
        intensity = d.double(forKey: "intensity")
        clearAngle = d.double(forKey: "clearAngle")
        fullAngle = d.double(forKey: "fullAngle")
        sound = d.bool(forKey: "sound")
    }

    /// Maps a hinge angle in degrees to 0 (clear) ... 1 (full fold).
    func amount(forAngle angle: Double) -> Double {
        guard clearAngle > fullAngle else { return 0 }
        let k = (clearAngle - angle) / (clearAngle - fullAngle)
        let c = min(max(k, 0), 1)
        return c * c * (3 - 2 * c) * intensity   // smoothstep
    }
}
