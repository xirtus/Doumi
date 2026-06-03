import Foundation
import AppKit
@preconcurrency import DoumiCore

struct LogEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let message: String
    let actionIcon: String
    let filename: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var config: DoumiConfig = .init()
    @Published var isRunning = false
    @Published var previewMode = false      // dry-run: show what rules would do
    @Published var activityLog: [LogEntry] = []
    @Published var configURL: URL = DoumiConfig.defaultConfigURL()
    @Published var selectedWatcher: WatcherConfig? = nil
    @Published var errorMessage: String? = nil

    private var engine: Engine?
    private var fsWatcher: DirectoryWatcher?

    init() {
        reloadConfig()
        setupLogSink()
        startWatching()
    }

    func reloadConfig() {
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            errorMessage = "Config file not found at \(configURL.path).\nCreate one to get started."
            return
        }
        do {
            config = try DoumiConfig.load(from: configURL)
            errorMessage = nil
            if selectedWatcher == nil { selectedWatcher = config.watch.first }
        } catch {
            errorMessage = "Config error: \(error.localizedDescription)"
        }
    }

    func startWatching() {
        guard !isRunning, !config.watch.isEmpty else { return }
        let eng = Engine(config: config, dryRun: previewMode || config.global.dryRun)
        engine = eng
        let enabled = config.watch.filter { $0.enabled }
        guard !enabled.isEmpty else { return }
        let fw = DirectoryWatcher(engine: eng, watchers: enabled)
        fsWatcher = fw
        fw.start()
        isRunning = true
    }

    func stopWatching() {
        fsWatcher?.stop()
        fsWatcher = nil
        engine = nil
        isRunning = false
        Logger.info("Doumi stopped.")
    }

    func restart() {
        stopWatching()
        reloadConfig()
        startWatching()
    }

    func runNow(watcher: WatcherConfig? = nil) {
        let cfg = self.config
        let dry = previewMode || cfg.global.dryRun
        let watchers = watcher.map { [$0] } ?? cfg.watch.filter { $0.enabled }
        DispatchQueue.global(qos: .utility).async {
            let eng = Engine(config: cfg, dryRun: dry)
            for w in watchers { eng.scanDirectory(watcher: w) }
        }
    }

    // Opens NSOpenPanel and appends a new watcher block to config.yaml
    func promptAddFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder for Doumi to watch"
        panel.prompt = "Add Folder"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor [weak self] in self?.appendFolderToConfig(url: url) }
        }
    }

    func appendFolderToConfig(url: URL) {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path.hasPrefix(home + "/")
            ? "~" + String(url.path.dropFirst(home.count))
            : url.path
        let name = url.lastPathComponent
        let snippet = "\n  - name: \(name)\n    path: \(path)\n    recursive: false\n    rules: []\n"

        let dir = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        var existing = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        if existing.contains("watch:") {
            // Find last entry in watch list and append after it
            existing += snippet
        } else {
            existing += "\nwatch:\n" + snippet
        }
        do {
            try existing.write(to: configURL, atomically: true, encoding: .utf8)
            restart()
        } catch {
            errorMessage = "Could not save config: \(error.localizedDescription)"
        }
    }

    func togglePreviewMode() {
        previewMode.toggle()
        if isRunning { stopWatching(); startWatching() }
        Logger.info(previewMode ? "Preview mode ON — rules will not execute" : "Preview mode OFF — rules active")
    }

    func openConfigInEditor() {
        let url = configURL
        if !FileManager.default.fileExists(atPath: url.path) {
            createDefaultConfig()
        }
        NSWorkspace.shared.open(url)
    }

    func createDefaultConfig() {
        let dir = configURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let exampleURL = Bundle.main.url(forResource: "config.example", withExtension: "yaml")
        if let src = exampleURL {
            try? FileManager.default.copyItem(at: src, to: configURL)
        } else {
            let stub = """
# Doumi Configuration
# See https://github.com/your-org/Doumi for documentation

global:
  dry_run: false
  log_level: info

watch:
  - name: Desktop Cleanup
    path: ~/Desktop
    recursive: false
    rules:
      - name: Sort Screenshots
        conditions:
          - type: name
            starts_with: "Screenshot"
          - type: extension
            one_of: [png, jpg]
        actions:
          - type: move
            to: ~/Pictures/Screenshots/{year}-{month}/
"""
            try? stub.write(to: configURL, atomically: true, encoding: .utf8)
        }
    }

    private func setupLogSink() {
        Logger.level = config.global.logLevel
        Logger.sink = { [weak self] line in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let icon: String
                let lower = line.lowercased()
                if lower.contains("move") { icon = "arrow.right.circle.fill" }
                else if lower.contains("delete") || lower.contains("trash") { icon = "trash.fill" }
                else if lower.contains("rename") { icon = "pencil.circle.fill" }
                else if lower.contains("copy") { icon = "doc.on.doc.fill" }
                else if lower.contains("run") { icon = "terminal.fill" }
                else if lower.contains("notify") { icon = "bell.fill" }
                else if lower.contains("error") { icon = "exclamationmark.triangle.fill" }
                else if lower.contains("warn") { icon = "exclamationmark.circle.fill" }
                else { icon = "info.circle.fill" }

                // Extract filename hint
                let filename: String
                if let range = line.range(of: "✓ rule '.*': (.+)", options: .regularExpression),
                   let fn = line[range].components(separatedBy: ": ").last {
                    filename = fn
                } else { filename = "" }

                let entry = LogEntry(message: line, actionIcon: icon, filename: filename)
                self.activityLog.insert(entry, at: 0)
                if self.activityLog.count > 500 { self.activityLog = Array(self.activityLog.prefix(500)) }
            }
        }
    }
}
