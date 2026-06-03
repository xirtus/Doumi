import SwiftUI
import DoumiCore

struct SettingsView: View {
    @EnvironmentObject var state: AppState
    @State private var configPathText: String = ""

    var body: some View {
        Form {
            Section("Config File") {
                LabeledContent("Location") {
                    HStack(spacing: 6) {
                        Text(state.configURL.path.replacingOccurrences(
                            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospaced()
                            .lineLimit(1)
                        Spacer()
                        Button("Edit") { state.openConfigInEditor() }
                            .buttonStyle(.bordered)
                        Button("Reload") { state.restart() }
                            .buttonStyle(.bordered)
                    }
                }
                if let err = state.errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }

            Section("Daemon") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(state.isRunning ? Color.green : Color.gray)
                            .frame(width: 8, height: 8)
                        Text(state.isRunning
                             ? "Watching \(state.config.watch.filter(\.enabled).count) folder(s)"
                             : "Stopped")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(state.isRunning ? "Stop" : "Start") {
                            if state.isRunning { state.stopWatching() } else { state.restart() }
                        }
                        .buttonStyle(.bordered)
                    }
                }

                LabeledContent("Log Level") {
                    Picker("", selection: Binding(
                        get: { state.config.global.logLevel },
                        set: { _ in }
                    )) {
                        ForEach(LogLevel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 120)
                    .disabled(true)
                    .help("Change in config file")
                }

                LabeledContent("Dry Run") {
                    Toggle("", isOn: .constant(state.config.global.dryRun))
                        .disabled(true)
                        .help("Change in config file")
                }
            }

            Section("LaunchAgent") {
                LabeledContent("Auto-start at login") {
                    HStack {
                        Text(launchAgentInstalled ? "Installed" : "Not installed")
                            .foregroundStyle(.secondary)
                        Spacer()
                        if launchAgentInstalled {
                            Button("Remove") { uninstallLaunchAgent() }
                                .buttonStyle(.bordered)
                                .foregroundStyle(.red)
                        } else {
                            Button("Install") { installLaunchAgent() }
                                .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            Section("About") {
                LabeledContent("Version", value: "0.1.0")
                LabeledContent("License", value: "MIT")
                LabeledContent("Source") {
                    Link("github.com/your-org/Doumi",
                         destination: URL(string: "https://github.com")!)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }

    private var launchAgentInstalled: Bool {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.doumi.app.plist").path
        return FileManager.default.fileExists(atPath: path)
    }

    private func installLaunchAgent() {
        let exe = Bundle.main.executablePath ?? ProcessInfo.processInfo.arguments[0]
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>Label</key><string>com.doumi.app</string>
    <key>ProgramArguments</key><array><string>\(exe)</string></array>
    <key>RunAtLoad</key><true/>
    <key>StandardOutPath</key><string>\(home)/Library/Logs/doumi-app.log</string>
    <key>StandardErrorPath</key><string>\(home)/Library/Logs/doumi-app.error.log</string>
</dict></plist>
"""
        let dir = "\(home)/Library/LaunchAgents"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = "\(dir)/com.doumi.app.plist"
        try? plist.write(toFile: path, atomically: true, encoding: .utf8)
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["load", path]; try? p.run(); p.waitUntilExit()
    }

    private func uninstallLaunchAgent() {
        let path = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/com.doumi.app.plist").path
        let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = ["unload", path]; try? p.run(); p.waitUntilExit()
        try? FileManager.default.removeItem(atPath: path)
    }
}
