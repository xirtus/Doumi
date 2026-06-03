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
    @Published var previewMode = false
    @Published var activityLog: [LogEntry] = []
    @Published var configURL: URL = DoumiConfig.defaultConfigURL()
    @Published var selectedWatcher: WatcherConfig? = nil
    @Published var errorMessage: String? = nil

    // Pending settings (edited in SettingsView, applied on save)
    @Published var pendingDryRun: Bool = false
    @Published var pendingLogLevel: LogLevel = .info
    @Published var pendingTrash: TrashSettings = .init()
    @Published var pendingSettingsChanges: Bool = false

    private var engine: Engine?
    private var fsWatcher: DirectoryWatcher?
    private var trashTimer: Timer?

    init() {
        reloadConfig()
        setupLogSink()
        startWatching()
        scheduleTrashChecks()
    }

    func reloadConfig() {
        let previousPath = selectedWatcher?.path
        guard FileManager.default.fileExists(atPath: configURL.path) else {
            errorMessage = "Config file not found at \(configURL.path).\nCreate one to get started."
            return
        }
        do {
            config = try DoumiConfig.load(from: configURL)
            errorMessage = nil
            if let path = previousPath {
                selectedWatcher = config.watch.first(where: { $0.path == path }) ?? config.watch.first
            } else {
                selectedWatcher = config.watch.first
            }
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

    // MARK: - Config persistence

    func saveConfig() throws {
        let yaml = try config.toYAML()
        let dir = configURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try yaml.write(to: configURL, atomically: true, encoding: .utf8)
    }

    // MARK: - Rule CRUD

    func addRule(_ rule: RuleConfig, toFolderPath folderPath: String) {
        if let wi = config.watch.firstIndex(where: { $0.path == folderPath }) {
            config.watch[wi].rules.append(rule)
            if selectedWatcher?.path == folderPath { selectedWatcher = config.watch[wi] }
        } else {
            var watcher = WatcherConfig(path: folderPath)
            watcher.rules = [rule]
            config.watch.append(watcher)
            selectedWatcher = config.watch.last
        }
        do { try saveConfig() } catch { errorMessage = "Could not save: \(error.localizedDescription)" }
        if isRunning { stopWatching(); startWatching() }
    }

    // MARK: - Rule enable/disable toggle

    func toggleRule(_ ruleID: UUID, inWatcher watcherID: UUID) {
        guard let wi = config.watch.firstIndex(where: { $0.id == watcherID }),
              let ri = config.watch[wi].rules.firstIndex(where: { $0.id == ruleID }) else { return }
        config.watch[wi].rules[ri].enabled.toggle()
        if selectedWatcher?.id == watcherID {
            selectedWatcher = config.watch[wi]
        }
        do {
            try saveConfig()
        } catch {
            errorMessage = "Could not save config: \(error.localizedDescription)"
        }
        if isRunning {
            stopWatching()
            startWatching()
        }
    }

    // MARK: - Pending settings

    func loadPendingSettings() {
        pendingDryRun = config.global.dryRun
        pendingLogLevel = config.global.logLevel
        pendingTrash = config.global.trash
        pendingSettingsChanges = false
    }

    func applyPendingSettings() {
        config.global.dryRun = pendingDryRun
        config.global.logLevel = pendingLogLevel
        config.global.trash = pendingTrash
        pendingSettingsChanges = false
        do {
            try saveConfig()
        } catch {
            errorMessage = "Could not save config: \(error.localizedDescription)"
            return
        }
        Logger.level = config.global.logLevel
        if isRunning {
            stopWatching()
            startWatching()
        }
        scheduleTrashChecks()
    }

    func discardPendingSettings() {
        loadPendingSettings()
    }

    // MARK: - Folder management

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

    // MARK: - Trash management

    private func scheduleTrashChecks() {
        trashTimer?.invalidate()
        guard config.global.trash.scheduledDeletion || config.global.trash.sizeBasedDeletion else { return }
        checkAndCleanTrash()
        trashTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkAndCleanTrash() }
        }
    }

    func checkAndCleanTrash() {
        let settings = config.global.trash
        guard settings.scheduledDeletion || settings.sizeBasedDeletion else { return }
        let trashURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        Task.detached(priority: .background) {
            await AppState.cleanTrash(trashURL: trashURL, settings: settings)
        }
    }

    private static func cleanTrash(trashURL: URL, settings: TrashSettings) async {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: trashURL, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isDirectoryKey]
        ) else { return }

        var itemInfo: [(url: URL, date: Date, size: Int64)] = []
        for item in items {
            let vals = try? item.resourceValues(forKeys: [.contentModificationDateKey])
            let date = vals?.contentModificationDate ?? Date()
            let size = AppState.itemSize(at: item)
            itemInfo.append((item, date, size))
        }

        if settings.scheduledDeletion {
            let cutoff = Date().addingTimeInterval(-Double(settings.deleteAfterDays) * 86400)
            for info in itemInfo where info.date < cutoff {
                try? FileManager.default.removeItem(at: info.url)
                Logger.info("Trash: deleted \(info.url.lastPathComponent) (older than \(settings.deleteAfterDays) days)")
            }
            itemInfo = itemInfo.filter { $0.date >= cutoff }
        }

        if settings.sizeBasedDeletion {
            let maxBytes = Int64(settings.maxSizeMB) * 1024 * 1024
            var totalSize = itemInfo.reduce(Int64(0)) { $0 + $1.size }
            if totalSize > maxBytes {
                let sorted = itemInfo.sorted { $0.date < $1.date }
                for info in sorted {
                    if totalSize <= maxBytes { break }
                    try? FileManager.default.removeItem(at: info.url)
                    totalSize -= info.size
                    Logger.info("Trash: deleted \(info.url.lastPathComponent) (size limit \(settings.maxSizeMB) MB)")
                }
            }
        }
    }

    private static func itemSize(at url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey], options: .skipsHiddenFiles
        ) else {
            return (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map { Int64($0) } ?? 0
        }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    // MARK: - Logging

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
