import SwiftUI
import ServiceManagement

// MARK: - Menu bar

struct MenuContent: View {
    @ObservedObject var engine = FoldEngine.shared
    @ObservedObject var settings = FoldSettings.shared

    var body: some View {
        Text(engine.sensorAvailable ? "Lid \(Int(engine.angle))°" : "No hinge sensor")

        Divider()

        Toggle("Fold Enabled", isOn: $settings.enabled)
        Toggle("Pause", isOn: $engine.paused)

        Picker("Style", selection: $settings.presetID) {
            ForEach(Preset.all) { Text($0.name).tag($0.id) }
        }

        Divider()

        Button("Show Me the Fold") { engine.demo() }

        Button("Settings…") { SettingsWindow.show() }
            .keyboardShortcut(",")
        Button("Quit GetDuo") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

// MARK: - Settings window

enum SettingsWindow {
    private static var window: NSWindow?

    static func show() {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
                             styleMask: [.titled, .closable],
                             backing: .buffered, defer: false)
            w.title = "GetDuo"
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView())
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var engine = FoldEngine.shared
    @ObservedObject var settings = FoldSettings.shared
    @State private var scrub: Double = 55
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            if !engine.hasPermission {
                Section { PermissionBanner() }
            }

            Section {
                preview
            } footer: {
                Text("Drag to preview any lid angle. The backlight cuts out well before the lid shuts, so the fold you actually see happens on the way open.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Style") { presets }

            Section {
                Toggle("Fold when the lid moves", isOn: $settings.enabled)
                LabeledContent("Intensity") {
                    Slider(value: $settings.intensity, in: 0.2...1).frame(width: 200)
                }
                Toggle("Chime when the screen clears", isOn: $settings.sound)
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        try? on ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
                    }
            }

            Section("Advanced") {
                angleRow("Starts folding below", $settings.clearAngle, 60...170)
                angleRow("Fully folded at", $settings.fullAngle, 20...90)
                LabeledContent("Hinge sensor", value: engine.sensorAvailable ? "Connected" : "Not found")
                LabeledContent("Screen Recording", value: engine.hasPermission ? "Allowed" : "Not allowed")
                Button("Reset to Defaults", action: reset)
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .onAppear { engine.refreshPermission() }
    }

    private var preview: some View {
        VStack(spacing: 10) {
            FoldPreview(preset: settings.preset, amount: settings.amount(forAngle: scrub))
                .frame(height: 210)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.12)))

            HStack(spacing: 10) {
                Image(systemName: "laptopcomputer.slash").foregroundStyle(.secondary)
                Slider(value: $scrub, in: 20...130)
                Image(systemName: "laptopcomputer").foregroundStyle(.secondary)
                Text("\(Int(scrub))°")
                    .font(.system(.callout, design: .rounded).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 38, alignment: .trailing)
            }
        }
    }

    private var presets: some View {
        HStack(spacing: 10) {
            ForEach(Preset.all) { preset in
                PresetCard(preset: preset, selected: settings.presetID == preset.id) {
                    settings.presetID = preset.id
                }
            }
        }
    }

    private func angleRow(_ title: String, _ value: Binding<Double>, _ range: ClosedRange<Double>) -> some View {
        LabeledContent(title) {
            HStack {
                Slider(value: value, in: range)
                Text("\(Int(value.wrappedValue))°").monospacedDigit()
                    .foregroundStyle(.secondary).frame(width: 38, alignment: .trailing)
            }
            .frame(width: 230)
        }
    }

    private func reset() {
        settings.presetID = "shade"
        settings.intensity = 1
        settings.clearAngle = 100
        settings.fullAngle = 35
    }
}

private struct PresetCard: View {
    let preset: Preset
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                Text(preset.name).font(.headline)
                Text(preset.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(selected ? 0.75 : 0.3)))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear), lineWidth: 2))
        }
        .buttonStyle(.plain)
    }
}

private struct PermissionBanner: View {
    @ObservedObject var engine = FoldEngine.shared

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.display").font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Screen Recording access needed").font(.headline)
                Text("Fold reshapes what is already on your display. Nothing leaves your Mac.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 6) {
                Button("Allow…") { engine.requestPermission() }
                    .buttonStyle(.borderedProminent)
                Button("Already Allowed? Restart") { engine.relaunch() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.orange.opacity(0.12)))
    }
}
