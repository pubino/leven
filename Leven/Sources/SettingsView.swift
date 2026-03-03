import SwiftUI

struct SettingsView: View {
    @State private var permissionGranted = CGPreflightScreenCaptureAccess()
    @State private var didReset = false

    var body: some View {
        Form {
            Section {
                LabeledContent("Screen Recording Permission") {
                    HStack(spacing: 8) {
                        Image(systemName: permissionGranted ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(permissionGranted ? .green : .red)
                        Text(permissionGranted ? "Granted" : "Not Granted")
                        Button {
                            permissionGranted = CGPreflightScreenCaptureAccess()
                        } label: {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .help("Refresh permission status")
                    }
                }

                HStack {
                    Button("Reset Permission") {
                        resetPermission()
                    }
                    .disabled(didReset)

                    Button("Open System Settings") {
                        openScreenRecordingSettings()
                    }
                }

                if didReset {
                    Text("Permission reset. Restart the app for macOS to prompt again.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450)
    }

    private func resetPermission() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "ScreenCapture", "com.leven.app"]
        do {
            try process.run()
            process.waitUntilExit()
            permissionGranted = CGPreflightScreenCaptureAccess()
            didReset = true
        } catch {
            // tccutil failed — unlikely but not critical
        }
    }

    private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
}
