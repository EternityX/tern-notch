import AppKit
import SwiftUI

@MainActor
final class SettingsWindow {
    static let shared = SettingsWindow()
    private var window: NSWindow?
    var store: Store?

    func show() {
        guard let store else { return }
        if window == nil {
            let host = NSHostingController(rootView: SettingsView(store: store, prefs: .shared))
            let window = NSWindow(contentViewController: host)
            window.title = "Agent Notch Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setContentSize(NSSize(width: 520, height: 640))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var store: Store
    @ObservedObject var prefs: Preferences

    var body: some View {
        Form {
            Section("Opening") {
                Picker("Open the notch", selection: $prefs.openOn) {
                    ForEach(Preferences.OpenTrigger.allCases) { Text($0.title).tag($0) }
                }
                if prefs.openOn == .hover {
                    LabeledContent("Hover delay") {
                        Slider(value: $prefs.hoverDelay, in: 0...0.6, step: 0.02) {
                            Text("Hover delay")
                        } minimumValueLabel: { Text("0") } maximumValueLabel: { Text(seconds(prefs.hoverDelay)) }
                            .labelsHidden()
                    }
                }
                LabeledContent("Close after leaving") {
                    Slider(value: $prefs.closeDelay, in: 0.1...1.5, step: 0.05) {
                        Text("Close after leaving")
                    } minimumValueLabel: { Text("0.1 s") } maximumValueLabel: { Text(seconds(prefs.closeDelay)) }
                        .labelsHidden()
                }
                Toggle("Haptic feedback when it opens", isOn: $prefs.haptics)
            }

            Section("Closed notch") {
                Picker("Beside the notch", selection: $prefs.glance) {
                    ForEach(Preferences.Glance.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Shrink to the notch when no agent is busy", isOn: $prefs.shrinkWhenIdle)
                Toggle("Blink while an agent waits for you", isOn: $prefs.blink)
                Toggle("Play a sound when an agent asks something", isOn: $prefs.soundOnAsk)
            }

            Section("Panel") {
                Picker("Width", selection: $prefs.width) {
                    ForEach(Preferences.PanelWidth.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                LabeledContent("Glass darkness") {
                    Slider(value: $prefs.glassDarkness, in: 0...0.8) {
                        Text("Glass darkness")
                    } minimumValueLabel: { Image(systemName: "sun.max") } maximumValueLabel: { Image(systemName: "moon.fill") }
                        .labelsHidden()
                }
            }

            Section("Display") {
                Picker("Show on", selection: $prefs.display) {
                    ForEach(Preferences.Display.allCases) { Text($0.title).tag($0) }
                }
                Toggle("Show over full-screen apps", isOn: $prefs.overFullScreen)
            }

            Section {
                if store.quotas.isEmpty {
                    Text("No usage limits reported yet.").foregroundStyle(.secondary)
                } else {
                    ForEach(store.quotas) { quota in UsageRow(quota: quota) }
                }
            } header: {
                Text("Usage")
            } footer: {
                Text("From `omp usage`, refreshed every two minutes.").foregroundStyle(.secondary)
            }

            Section("About") {
                LabeledContent("Tern") {
                    Text(store.live ? "Connected" : "Waiting for Tern…")
                        .foregroundStyle(store.live ? Color.green : Color.secondary)
                }
                LabeledContent("Version") {
                    Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                }
                Button("Quit Agent Notch", role: .destructive) { NSApp.terminate(nil) }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 480, minHeight: 560)
    }

    private func seconds(_ value: Double) -> String {
        String(format: "%.2g s", value)
    }
}

struct UsageRow: View {
    let quota: Quota

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(quota.label)
                Spacer()
                Text(percent(quota.used)).monospacedDigit().fontWeight(.semibold)
            }
            ProgressView(value: min(max(quota.used, 0), 1))
                .tint(quota.used < 0.6 ? .green : quota.used < 0.85 ? .yellow : .red)
            if let resets = quota.resetsAt {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text("Resets in \(duration(until: resets / 1000, from: context.date)) · \(quota.provider)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
