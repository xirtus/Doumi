import Foundation
import Yams

// MARK: - Top-level

public struct DoumiConfig: Codable {
    public var global: GlobalConfig = .init()
    public var watch: [WatcherConfig] = []
    public init() {}
}

public struct TrashSettings: Codable, Equatable {
    public var scheduledDeletion: Bool = false
    public var deleteAfterDays: Int = 30
    public var sizeBasedDeletion: Bool = false
    public var maxSizeMB: Int = 5000
    public init() {}
    enum CodingKeys: String, CodingKey {
        case scheduledDeletion = "scheduled_deletion"
        case deleteAfterDays = "delete_after_days"
        case sizeBasedDeletion = "size_based_deletion"
        case maxSizeMB = "max_size_mb"
    }
}

public struct GlobalConfig: Codable {
    public var dryRun: Bool = false
    public var logLevel: LogLevel = .info
    public var trash: TrashSettings = .init()
    public init() {}
    enum CodingKeys: String, CodingKey {
        case dryRun = "dry_run"; case logLevel = "log_level"; case trash
    }
}

public enum LogLevel: String, Codable, CaseIterable, Comparable {
    case debug, info, warn, error
    static private let order: [LogLevel] = [.debug, .info, .warn, .error]
    public static func < (l: Self, r: Self) -> Bool {
        order.firstIndex(of: l)! < order.firstIndex(of: r)!
    }
}

public struct WatcherConfig: Codable, Identifiable {
    public var id: UUID = UUID()
    public var name: String?
    public var path: String
    public var recursive: Bool = false
    public var enabled: Bool = true
    public var rules: [RuleConfig] = []
    public init(path: String) { self.path = path }
    enum CodingKeys: String, CodingKey {
        case name, path, recursive, enabled, rules
    }
}

public struct RuleConfig: Codable, Identifiable {
    public var id: UUID = UUID()
    public var name: String?
    public var match: MatchMode = .all
    public var conditions: [Condition] = []
    public var actions: [Action] = []
    public var enabled: Bool = true
    public var stop: Bool = true
    public init() {}
    enum CodingKeys: String, CodingKey {
        case name, match, conditions, actions, enabled, stop
    }
}

public enum MatchMode: String, Codable { case all, any, none }

// MARK: - Conditions

public struct Condition: Codable {
    public let type: ConditionType
    public var glob: String?; public var regex: String?; public var equals: String?
    public var contains: String?; public var startsWith: String?; public var endsWith: String?
    public var notGlob: String?; public var oneOf: [String]?; public var not: String?
    public var notOneOf: [String]?; public var gt: String?; public var lt: String?
    public var gte: String?; public var lte: String?; public var olderThan: String?
    public var newerThan: String?; public var inTheNext: String?; public var notInTheNext: String?
    public var basis: AgeBasis?; public var run: String?
    // Absolute date / time-of-day
    public var beforeDate: String?; public var afterDate: String?
    public var atTime: String?; public var beforeTime: String?; public var afterTime: String?
    // Meta operators
    public var isBlank: Bool?; public var didChange: Bool?
    // Numeric (depth, count)
    public var depth: Int?; public var fileCount: Int?
    // Extra typed values
    public var colorLabelValue: Int?; public var locked: Bool?

    public init(type: ConditionType) { self.type = type }

    enum CodingKeys: String, CodingKey {
        case type, glob, regex, contains, run, not, depth, locked
        case equals = "is"; case startsWith = "starts_with"; case endsWith = "ends_with"
        case notGlob = "not_glob"; case oneOf = "one_of"; case notOneOf = "not_one_of"
        case gt, lt, gte, lte
        case olderThan = "older_than"; case newerThan = "newer_than"
        case inTheNext = "in_the_next"; case notInTheNext = "not_in_the_next"
        case basis
        case beforeDate = "before_date"; case afterDate = "after_date"
        case atTime = "at_time"; case beforeTime = "before_time"; case afterTime = "after_time"
        case isBlank = "is_blank"; case didChange = "did_change"
        case fileCount = "file_count"; case colorLabelValue = "color_label_value"
    }
}

public enum ConditionType: String, Codable {
    case name; case ext = "extension"; case size, age, kind, script, tags
    case fullName    = "full_name"
    case colorLabel  = "color_label"
    case comment
    case locked
    case contents
    case sourceURL   = "source_url"
    case subfolderDepth = "subfolder_depth"
    case subItemCount   = "sub_item_count"
    case anyFile     = "any_file"
    case currentTime = "current_time"
    case passesAppleScript = "passes_applescript"
    case passesJavaScript  = "passes_javascript"
}
public enum AgeBasis: String, Codable { case modified, created }

// MARK: - Actions

public struct Action: Codable {
    public let type: ActionType
    public var to: String?; public var createDirs: Bool?; public var onConflict: ConflictStrategy?
    public var command: String?; public var message: String?; public var title: String?
    public var with: String?
    public init(type: ActionType) { self.type = type }
    enum CodingKeys: String, CodingKey {
        case type, to, message, title, with, command
        case createDirs = "create_dirs"; case onConflict = "on_conflict"
    }
}

public enum ActionType: String, Codable {
    case move; case fileCopy = "copy"; case rename; case trash; case delete
    case run; case notify; case log; case openWith = "open"
    case removeTags      = "remove_tags"
    case addComment      = "add_comment"
    case toggleExtension = "toggle_extension"
    case toggleLock      = "toggle_lock"
    case archive
    case unarchive
    case importMusic     = "import_music"
    case importPhotos    = "import_photos"
    case importTV        = "import_tv"
    case runJavaScript   = "run_javascript"
    case runAutomator    = "run_automator"
    case continueMatching = "continue_matching"
}
public enum ConflictStrategy: String, Codable { case rename, skip, overwrite, error }

// MARK: - Custom decoders

extension DoumiConfig {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CK.self)
        global = try c.decodeIfPresent(GlobalConfig.self, forKey: .global) ?? .init()
        watch  = try c.decodeIfPresent([WatcherConfig].self, forKey: .watch) ?? []
    }
    private enum CK: String, CodingKey { case global, watch }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CK.self)
        try c.encode(global, forKey: .global)
        try c.encode(watch, forKey: .watch)
    }
}

extension GlobalConfig {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dryRun   = try c.decodeIfPresent(Bool.self, forKey: .dryRun) ?? false
        logLevel = try c.decodeIfPresent(LogLevel.self, forKey: .logLevel) ?? .info
        trash    = try c.decodeIfPresent(TrashSettings.self, forKey: .trash) ?? .init()
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(dryRun, forKey: .dryRun)
        try c.encode(logLevel, forKey: .logLevel)
        if trash != TrashSettings() {
            try c.encode(trash, forKey: .trash)
        }
    }
}

extension WatcherConfig {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = UUID()
        name      = try c.decodeIfPresent(String.self, forKey: .name)
        path      = try c.decode(String.self, forKey: .path)
        recursive = try c.decodeIfPresent(Bool.self, forKey: .recursive) ?? false
        enabled   = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        rules     = try c.decodeIfPresent([RuleConfig].self, forKey: .rules) ?? []
    }
}

extension RuleConfig {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id         = UUID()
        name       = try c.decodeIfPresent(String.self, forKey: .name)
        match      = try c.decodeIfPresent(MatchMode.self, forKey: .match) ?? .all
        conditions = try c.decodeIfPresent([Condition].self, forKey: .conditions) ?? []
        actions    = try c.decodeIfPresent([Action].self, forKey: .actions) ?? []
        enabled    = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        stop       = try c.decodeIfPresent(Bool.self, forKey: .stop) ?? true
    }
}

extension Condition {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(glob, forKey: .glob)
        try c.encodeIfPresent(regex, forKey: .regex)
        try c.encodeIfPresent(equals, forKey: .equals)
        try c.encodeIfPresent(contains, forKey: .contains)
        try c.encodeIfPresent(startsWith, forKey: .startsWith)
        try c.encodeIfPresent(endsWith, forKey: .endsWith)
        try c.encodeIfPresent(notGlob, forKey: .notGlob)
        try c.encodeIfPresent(oneOf, forKey: .oneOf)
        try c.encodeIfPresent(not, forKey: .not)
        try c.encodeIfPresent(notOneOf, forKey: .notOneOf)
        try c.encodeIfPresent(gt, forKey: .gt)
        try c.encodeIfPresent(lt, forKey: .lt)
        try c.encodeIfPresent(gte, forKey: .gte)
        try c.encodeIfPresent(lte, forKey: .lte)
        try c.encodeIfPresent(olderThan, forKey: .olderThan)
        try c.encodeIfPresent(newerThan, forKey: .newerThan)
        try c.encodeIfPresent(inTheNext, forKey: .inTheNext)
        try c.encodeIfPresent(notInTheNext, forKey: .notInTheNext)
        try c.encodeIfPresent(basis, forKey: .basis)
        try c.encodeIfPresent(run, forKey: .run)
        try c.encodeIfPresent(beforeDate, forKey: .beforeDate)
        try c.encodeIfPresent(afterDate, forKey: .afterDate)
        try c.encodeIfPresent(atTime, forKey: .atTime)
        try c.encodeIfPresent(beforeTime, forKey: .beforeTime)
        try c.encodeIfPresent(afterTime, forKey: .afterTime)
        try c.encodeIfPresent(isBlank, forKey: .isBlank)
        try c.encodeIfPresent(didChange, forKey: .didChange)
        try c.encodeIfPresent(depth, forKey: .depth)
        try c.encodeIfPresent(fileCount, forKey: .fileCount)
        try c.encodeIfPresent(colorLabelValue, forKey: .colorLabelValue)
        try c.encodeIfPresent(locked, forKey: .locked)
    }
}

extension Action {
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(to, forKey: .to)
        try c.encodeIfPresent(createDirs, forKey: .createDirs)
        try c.encodeIfPresent(onConflict, forKey: .onConflict)
        try c.encodeIfPresent(command, forKey: .command)
        try c.encodeIfPresent(message, forKey: .message)
        try c.encodeIfPresent(title, forKey: .title)
        try c.encodeIfPresent(with, forKey: .with)
    }
}

// MARK: - Loading & Saving

extension DoumiConfig {
    public static func load(from url: URL) throws -> DoumiConfig {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try YAMLDecoder().decode(DoumiConfig.self, from: text)
    }

    public func toYAML() throws -> String {
        return try YAMLEncoder().encode(self)
    }

    public static func defaultConfigURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/doumi/config.yaml")
    }
}

// MARK: - Errors

public enum DoumiError: LocalizedError {
    case destinationExists(URL), tooManyConflicts(URL), configNotFound(URL)
    public var errorDescription: String? {
        switch self {
        case .destinationExists(let u):  return "Destination exists: \(u.path)"
        case .tooManyConflicts(let u):   return "Too many conflicts: \(u.path)"
        case .configNotFound(let u):     return "Config not found: \(u.path)"
        }
    }
}
