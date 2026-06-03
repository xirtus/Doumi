internal import Foundation
internal import CoreServices

// MARK: - Logger

public enum Logger {
    private static let stateLock = NSLock()
    nonisolated(unsafe) private static var _level: LogLevel = .info
    nonisolated(unsafe) private static var _sink: (@Sendable (String) -> Void)? = nil

    public static var level: LogLevel {
        get { stateLock.withLock { _level } }
        set { stateLock.withLock { _level = newValue } }
    }

    public static var sink: (@Sendable (String) -> Void)? {
        get { stateLock.withLock { _sink } }
        set { stateLock.withLock { _sink = newValue } }
    }

    public static func debug(_ msg: String) { emit(msg, level: .debug, tag: "DEBUG") }
    public static func info (_ msg: String) { emit(msg, level: .info,  tag: "     ") }
    public static func warn (_ msg: String) { emit(msg, level: .warn,  tag: "WARN ") }
    public static func error(_ msg: String) { emit(msg, level: .error, tag: "ERROR") }

    private static func emit(_ msg: String, level req: LogLevel, tag: String) {
        let (currentLevel, currentSink) = stateLock.withLock { (_level, _sink) }
        guard currentLevel <= req else { return }
        let line = "[\(ts())] \(tag) \(msg)"
        print(line)
        currentSink?(line)
    }
    private static func ts() -> String {
        Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits))
    }
}

// MARK: - DirectoryWatcher

public final class DirectoryWatcher: @unchecked Sendable {
    private let engine: Engine
    private let watchers: [WatcherConfig]
    private let debounceInterval: TimeInterval = 0.5

    // All mutable state lives behind `stateLock`.
    private let stateLock = NSLock()
    private var streams: [FSEventStreamRef] = []
    private var lastSeen: [String: Date] = [:]

    public init(engine: Engine, watchers: [WatcherConfig]) {
        self.engine = engine
        self.watchers = watchers
    }

    /// Set up FSEvent streams — non-blocking. Call from GUI or CLI.
    public func start() {
        var created = 0
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
            stateLock.withLock { streams.append(stream) }
            created += 1
        }
        Logger.info("Doumi running — \(created) folder(s) active")
    }

    /// Start and block forever — for CLI use.
    public func startBlocking() {
        start()
        dispatchMain()
    }

    public func stop() {
        let toStop = stateLock.withLock { () -> [FSEventStreamRef] in
            let s = streams; streams.removeAll(); return s
        }
        for s in toStop {
            FSEventStreamStop(s); FSEventStreamInvalidate(s); FSEventStreamRelease(s)
        }
    }

    /// Called from the FSEvents callback. Debounces and dispatches to the engine.
    fileprivate func handleEvent(path: String, watcher: WatcherConfig) {
        let shouldProcess = stateLock.withLock { () -> Bool in
            let now = Date()
            if let last = lastSeen[path], now.timeIntervalSince(last) < debounceInterval {
                return false
            }
            lastSeen[path] = now
            return true
        }
        guard shouldProcess else { return }

        let url = URL(filePath: path)
        Logger.debug("Event: \(url.lastPathComponent)")
        engine.handle(url: url, watcher: watcher)
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
                box.watcher.handleEvent(path: path, watcher: box.config)
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
