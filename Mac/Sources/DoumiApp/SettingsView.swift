import SwiftUI
import DoumiCore

struct SettingsView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            configFileSection
            daemonSection
            trashSection
            launchAgentSection
            aboutSection
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .onAppear { state.loadPendingSettings() }
        .toolbar {
            if state.pendingSettingsChanges {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button("Revert") { state.discardPendingSettings() }
                        .buttonStyle(.bordered)
                    Button("Apply") { state.applyPendingSettings() }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
    }

    // MARK: - Sections

    private var configFileSection: some View {
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
    }

    private var daemonSection: some View {
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
                    get: { state.pendingLogLevel },
                    set: { state.pendingLogLevel = $0; state.pendingSettingsChanges = true }
                )) {
                    ForEach(LogLevel.allCases, id: \.self) { Text($0.rawValue.capitalized).tag($0) }
                }
                .frame(width: 120)
            }

            LabeledContent("Dry Run") {
                Toggle("", isOn: Binding(
                    get: { state.pendingDryRun },
                    set: { state.pendingDryRun = $0; state.pendingSettingsChanges = true }
                ))
                .help("Preview mode — rules log what they'd do but don't act on files")
            }
        }
    }

    private var trashSection: some View {
        Section {
            // Scheduled deletion
            LabeledContent("Scheduled Deletion") {
                Toggle("", isOn: Binding(
                    get: { state.pendingTrash.scheduledDeletion },
                    set: { state.pendingTrash.scheduledDeletion = $0; state.pendingSettingsChanges = true }
                ))
                .help("Automatically delete Trash items older than the specified number of days")
            }

            if state.pendingTrash.scheduledDeletion {
                LabeledContent("Delete After") {
                    HStack(spacing: 8) {
                        Stepper(value: Binding(
                            get: { state.pendingTrash.deleteAfterDays },
                            set: { state.pendingTrash.deleteAfterDays = $0; state.pendingSettingsChanges = true }
                        ), in: 1...365, step: 1) {
                            EmptyView()
                        }
                        Text("\(state.pendingTrash.deleteAfterDays) day\(state.pendingTrash.deleteAfterDays == 1 ? "" : "s")")
                            .frame(width: 60, alignment: .leading)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            // Size-based deletion
            LabeledContent("Size-Based Deletion") {
                Toggle("", isOn: Binding(
                    get: { state.pendingTrash.sizeBasedDeletion },
                    set: { state.pendingTrash.sizeBasedDeletion = $0; state.pendingSettingsChanges = true }
                ))
                .help("Automatically delete oldest Trash items when total size exceeds the limit")
            }

            if state.pendingTrash.sizeBasedDeletion {
                LabeledContent("Max Trash Size") {
                    HStack(spacing: 8) {
                        Stepper(value: Binding(
                            get: { state.pendingTrash.maxSizeMB },
                            set: { state.pendingTrash.maxSizeMB = $0; state.pendingSettingsChanges = true }
                        ), in: 100...102400, step: 100) {
                            EmptyView()
                        }
                        Text(formatMB(state.pendingTrash.maxSizeMB))
                            .frame(width: 70, alignment: .leading)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if state.pendingTrash.scheduledDeletion || state.pendingTrash.sizeBasedDeletion {
                Button("Check Trash Now") {
                    state.applyPendingSettings()
                    state.checkAndCleanTrash()
                }
                .buttonStyle(.bordered)
            }
        } header: {
            Label("Trash Management", systemImage: "trash")
        } footer: {
            Text("Doumi checks the Trash hourly when the app is running. Items are deleted permanently — this cannot be undone.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var launchAgentSection: some View {
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
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: "0.1.0")
            LabeledContent("License", value: "MIT")
            LabeledContent("Source") {
                Link("github.com/your-org/Doumi",
                     destination: URL(string: "https://github.com")!)
            }
        }
    }

    // MARK: - Helpers

    private func formatMB(_ mb: Int) -> String {
        if mb >= 1024 { return String(format: "%.1f GB", Double(mb) / 1024) }
        return "\(mb) MB"
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
