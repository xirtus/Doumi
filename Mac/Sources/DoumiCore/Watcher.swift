import Foundation
import CoreServices

// MARK: - Logger

public enum Logger {
    public static var level: LogLevel = .info
    // Optional sink for the GUI to capture log lines
    public static var sink: ((String) -> Void)? = nil

    public static func debug(_ msg: String) { emit(msg, level: .debug, tag: "DEBUG") }
    public static func info (_ msg: String) { emit(msg, level: .info,  tag: "     ") }
    public static func warn (_ msg: String) { emit(msg, level: .warn,  tag: "WARN ") }
    public static func error(_ msg: String) { emit(msg, level: .error, tag: "ERROR") }

    private static func emit(_ msg: String, level req: LogLevel, tag: String) {
        guard Logger.level <= req else { return }
        let line = "[\(ts())] \(tag) \(msg)"
        print(line)
        sink?(line)
    }
    private static func ts() -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: Date())
    }
}

// MARK: - DirectoryWatcher

public final class DirectoryWatcher {
    private var streams: [FSEventStreamRef] = []
    private let engine: Engine
    private let watchers: [WatcherConfig]
    private var lastSeen: [String: Date] = [:]
    private let debounceInterval: TimeInterval = 0.5
    private let lock = NSLock()

    public init(engine: Engine, watchers: [WatcherConfig]) {
        self.engine = engine
        self.watchers = watchers
    }

    /// Set up FSEvent streams — non-blocking. Call from GUI or CLI.
    public func start() {
        for w in watchers {
            guard w.enabled else { continue }
            let rootPath = (w.path as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: rootPath) else {
                Logger.warn("Watch path does not exist: \(rootPath)"); continue
            }
            Logger.info("Watching: \(rootPath)\(w.recursive ? " (recursive)" : "")")
            guard let stream = makeStream(rootPath: rootPath, watcher: w) else {
                Logger.error("Failed to create FSEvent stream for: \(rootPath)"); continue
            }
            streams.append(stream)
        }
        Logger.info("Doumi running — \(streams.count) folder(s) active")
    }

    /// Start and block forever — for CLI use.
    public func startBlocking() {
        start()
        dispatchMain()
    }

    public func stop() {
        for s in streams { FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s) }
        streams.removeAll()
    }

    private func makeStream(rootPath: String, watcher: WatcherConfig) -> FSEventStreamRef? {
        let paths = [rootPath] as CFArray
        let box = CallbackBox(watcher: self, config: watcher)
        let boxPtr = Unmanaged.passRetained(box).toOpaque()

        var ctx = FSEventStreamContext(
            version: 0, info: boxPtr, retain: nil,
            release: { ptr in if let p = ptr { Unmanaged<CallbackBox>.fromOpaque(p).release() } },
            copyDescription: nil
        )

        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
        )

        let cb: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
            guard let info else { return }
            let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
            let pathArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
            let flagBuf = UnsafeBufferPointer(start: eventFlags, count: numEvents)

            for i in 0..<numEvents {
                guard let path = pathArray[i] as? String else { continue }
                let f = flagBuf[i]
                let isFile   = f & UInt32(kFSEventStreamEventFlagItemIsFile)    != 0
                let created  = f & UInt32(kFSEventStreamEventFlagItemCreated)   != 0
                let modified = f & UInt32(kFSEventStreamEventFlagItemModified)  != 0
                let renamed  = f & UInt32(kFSEventStreamEventFlagItemRenamed)   != 0
                guard isFile && (created || modified || renamed) else { continue }

                box.watcher.lock.lock()
                let now = Date()
                if let last = box.watcher.lastSeen[path],
                   now.timeIntervalSince(last) < box.watcher.debounceInterval {
                    box.watcher.lock.unlock(); continue
                }
                box.watcher.lastSeen[path] = now
                box.watcher.lock.unlock()

                let url = URL(fileURLWithPath: path)
                Logger.debug("Event: \(url.lastPathComponent)")
                box.watcher.engine.handle(url: url, watcher: box.config)
            }
        }

        guard let stream = FSEventStreamCreate(nil, cb, &ctx, paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), debounceInterval, flags) else { return nil }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
        FSEventStreamStart(stream)
        return stream
    }
}

private final class CallbackBox {
    let watcher: DirectoryWatcher
    let config: WatcherConfig
    init(watcher: DirectoryWatcher, config: WatcherConfig) { self.watcher = watcher; self.config = config }
}
