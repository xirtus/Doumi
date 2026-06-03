import Foundation
import ArgumentParser
import DoumiCore

// MARK: - Root command

struct Doumi: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doumi",
        abstract: "File automation daemon for macOS — open source Hazel alternative",
        version: "0.1.0",
        subcommands: [Watch.self, Run.self, Validate.self, Install.self, Uninstall.self],
        defaultSubcommand: Watch.self
    )
}

// MARK: - Shared options

struct SharedOptions: ParsableArguments {
    @Option(name: .shortAndLong, help: "Config file path")
    var config: String?

    @Flag(name: .shortAndLong, help: "Show what would happen without doing it")
    var dryRun: Bool = false

    @Flag(name: .shortAndLong, help: "Verbose output")
    var verbose: Bool = false

    func resolvedConfigURL() -> URL {
        if let c = config {
            return URL(filePath: (c as NSString).expandingTildeInPath)
        }
        return DoumiConfig.defaultConfigURL()
    }

    func loadConfig() throws -> DoumiConfig {
        let url = resolvedConfigURL()
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw DoumiError.configNotFound(url)
        }
        return try DoumiConfig.load(from: url)
    }

    func applyLogging(cfg: DoumiConfig) {
        Logger.level = verbose ? .debug : cfg.global.logLevel
    }
}

// MARK: - watch

struct Watch: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Watch directories and apply rules in the foreground"
    )

    @OptionGroup var opts: SharedOptions

    func run() throws {
        let cfg = try opts.loadConfig()
        opts.applyLogging(cfg: cfg)

        let engine = Engine(config: cfg, dryRun: opts.dryRun || cfg.global.dryRun)
        let enabled = cfg.watch.filter { $0.enabled }
        guard !enabled.isEmpty else {
            print("No enabled watchers in config.")
            return
        }

        let watcher = DirectoryWatcher(engine: engine, watchers: enabled)

        // Handle Ctrl+C gracefully
        let src = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        src.setEventHandler {
            print("\nDoumi stopped.")
            watcher.stop()
            Doumi.exit(withError: nil)
        }
        signal(SIGINT, SIG_IGN)
        src.resume()

        watcher.startBlocking()  // sets up streams then calls dispatchMain()
    }
}

// MARK: - run (one-shot scan)

struct Run: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Apply rules to existing files in watched directories (one-shot)"
    )

    @OptionGroup var opts: SharedOptions

    @Argument(help: "Specific path to process (defaults to all watched paths)")
    var path: String?

    func run() throws {
        let cfg = try opts.loadConfig()
        opts.applyLogging(cfg: cfg)

        let engine = Engine(config: cfg, dryRun: opts.dryRun || cfg.global.dryRun)

        for watcher in cfg.watch where watcher.enabled {
            let rootExpanded = (watcher.path as NSString).expandingTildeInPath

            if let target = path {
                let targetExpanded = (target as NSString).expandingTildeInPath
                guard targetExpanded.hasPrefix(rootExpanded) || rootExpanded == targetExpanded else {
                    continue
                }
            }

            let displayName = watcher.name ?? watcher.path
            Logger.info("Scanning '\(displayName)'…")
            engine.scanDirectory(watcher: watcher)
        }

        Logger.info("Done.")
    }
}

// MARK: - validate

struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Check config file for syntax errors"
    )

    @OptionGroup var opts: SharedOptions

    func run() throws {
        let url = opts.resolvedConfigURL()
        let cfg = try opts.loadConfig()

        print("✓ Config OK: \(url.path)")
        print("  \(cfg.watch.count) watcher(s)")
        for w in cfg.watch {
            let name = w.name ?? w.path
            let status = w.enabled ? "enabled" : "disabled"
            print("  • \(name) [\(status)] — \(w.rules.count) rule(s)")
            for r in w.rules {
                let rname = r.name ?? "<unnamed>"
                let rs = r.enabled ? "" : " [disabled]"
                print("    - \(rname)\(rs): \(r.conditions.count) condition(s), \(r.actions.count) action(s)")
            }
        }
    }
}

// MARK: - install / uninstall LaunchAgent

struct Install: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Install LaunchAgent to start Doumi automatically at login"
    )

    @OptionGroup var opts: SharedOptions

    func run() throws {
        let exePath = Bundle.main.executablePath
            ?? ProcessInfo.processInfo.arguments[0]
        let configPath = opts.resolvedConfigURL().path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let logsDir = "\(home)/Library/Logs"
        let agentsDir = "\(home)/Library/LaunchAgents"

        let plist = """
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.doumi.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>\(exePath)</string>
        <string>--config</string>
        <string>\(configPath)</string>
        <string>watch</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>\(logsDir)/doumi.log</string>
    <key>StandardErrorPath</key>
    <string>\(logsDir)/doumi.error.log</string>
</dict>
</plist>
"""
        try FileManager.default.createDirectory(atPath: agentsDir, withIntermediateDirectories: true)
        let plistPath = "\(agentsDir)/com.doumi.daemon.plist"
        try plist.write(toFile: plistPath, atomically: true, encoding: .utf8)

        let p = Process()
        p.executableURL = URL(filePath: "/bin/launchctl")
        p.arguments = ["load", plistPath]
        try p.run(); p.waitUntilExit()

        print("✓ Installed LaunchAgent: \(plistPath)")
        print("  Doumi will start automatically at login.")
        print("  Logs: \(logsDir)/doumi.log")
    }
}

struct Uninstall: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Remove the Doumi LaunchAgent"
    )

    func run() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let plistPath = "\(home)/Library/LaunchAgents/com.doumi.daemon.plist"

        let p = Process()
        p.executableURL = URL(filePath: "/bin/launchctl")
        p.arguments = ["unload", plistPath]
        try? p.run(); p.waitUntilExit()

        if FileManager.default.fileExists(atPath: plistPath) {
            try FileManager.default.removeItem(atPath: plistPath)
            print("✓ Removed LaunchAgent.")
        } else {
            print("LaunchAgent not installed.")
        }
    }
}
