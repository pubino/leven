import SwiftUI

struct ContentView: View {
    @StateObject private var appList = AppListProvider()
    @StateObject private var captureManager = AudioCaptureManager()
    @State private var selectedApp: RunningApp?

    var body: some View {
        VStack(spacing: 16) {
            // App picker dropdown
            HStack {
                Text("Application:")
                    .frame(width: 90, alignment: .leading)

                Picker("", selection: $selectedApp) {
                    Text("Select an app…").tag(RunningApp?.none)
                    ForEach(appList.apps) { app in
                        Text(app.name).tag(RunningApp?.some(app))
                    }
                }
                .labelsHidden()

                Button {
                    appList.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh app list")
            }

            // Recording duration
            if captureManager.state == .recording {
                Text(formatDuration(captureManager.duration))
                    .font(.system(.title2, design: .monospaced))
                    .foregroundStyle(.red)
            }

            // Stopped indicator
            if captureManager.state == .stopped {
                Text("Recording ready to save")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Error display
            if case .error(let message) = captureManager.state {
                Text(message)
                    .foregroundStyle(.red)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }

            // Buttons
            HStack(spacing: 12) {
                // Record / Stop button
                Button {
                    Task {
                        if captureManager.state == .recording {
                            await captureManager.stopCapture()
                        } else if let app = selectedApp {
                            await captureManager.startCapture(pid: app.id)
                        }
                    }
                } label: {
                    Label(
                        captureManager.state == .recording ? "Stop" : "Record",
                        systemImage: captureManager.state == .recording ? "stop.circle.fill" : "record.circle"
                    )
                    .frame(width: 80)
                }
                .disabled(selectedApp == nil && captureManager.state != .recording)
                .tint(captureManager.state == .recording ? .red : .accentColor)
                .keyboardShortcut("r", modifiers: .command)

                // Save button
                Button {
                    Task {
                        await captureManager.saveRecording()
                    }
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                        .frame(width: 80)
                }
                .disabled(!captureManager.hasRecording || captureManager.state == .recording || captureManager.state == .saving)
                .keyboardShortcut("s", modifiers: .command)
            }
        }
        .padding(24)
        .frame(minWidth: 400)
        .onChange(of: appList.apps) {
            // Clear selection if the selected app is no longer running
            if let selected = selectedApp, !appList.apps.contains(where: { $0.id == selected.id }) {
                selectedApp = nil
            }
        }
    }

    private func formatDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval) / 60
        let seconds = Int(interval) % 60
        let tenths = Int(interval * 10) % 10
        return String(format: "%02d:%02d.%d", minutes, seconds, tenths)
    }
}
