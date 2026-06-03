public import Foundation
internal import Darwin

public final class Engine: Sendable {
    public let config: DoumiConfig
    public let dryRun: Bool
    private let queue = DispatchQueue(label: "com.doumi.engine", qos: .utility)

    public init(config: DoumiConfig, dryRun: Bool) {
        self.config = config
        self.dryRun = dryRun
    }

    public func handle(url: URL, watcher: WatcherConfig) {
        queue.async {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            self.processFile(url: url, watcher: watcher)
        }
    }

    public func scanDirectory(watcher: WatcherConfig) {
        let fm = FileManager.default
        let rootPath = (watcher.path as NSString).expandingTildeInPath
        let rootURL = URL(filePath: rootPath)

        guard fm.fileExists(atPath: rootPath) else {
            Logger.warn("Path does not exist: \(rootPath)"); return
        }

        let opts: FileManager.DirectoryEnumerationOptions = watcher.recursive
            ? [] : [.skipsSubdirectoryDescendants]

        guard let enumerator = fm.enumerator(at: rootURL, includingPropertiesForKeys: nil, options: opts) else { return }
        for case let fileURL as URL in enumerator { processFile(url: fileURL, watcher: watcher) }
    }

    // MARK: - Rule matching

    private func processFile(url: URL, watcher: WatcherConfig) {
        for rule in watcher.rules {
            guard rule.enabled else { continue }
            guard matchesRule(url: url, rule: rule) else { continue }

            let name = rule.name ?? "<unnamed>"
            Logger.info("  ✓ rule '\(name)': \(url.lastPathComponent)")
            do {
                try executeActions(url: url, rule: rule)
            } catch {
                Logger.error("    error in '\(name)': \(error.localizedDescription)")
            }
            if rule.stop { break }
        }
    }

    private func matchesRule(url: URL, rule: RuleConfig) -> Bool {
        if rule.conditions.isEmpty { return true }
        switch rule.match {
        case .all:  return rule.conditions.allSatisfy { checkCondition(url: url, c: $0) }
        case .any:  return rule.conditions.contains   { checkCondition(url: url, c: $0) }
        case .none: return !rule.conditions.contains  { checkCondition(url: url, c: $0) }
        }
    }

    private func checkCondition(url: URL, c: Condition) -> Bool {
        switch c.type {
        case .name:              return checkName(url: url, c: c)
        case .fullName:          return checkFullName(url: url, c: c)
        case .ext:               return checkExtension(url: url, c: c)
        case .size:              return checkSize(url: url, c: c)
        case .age:               return checkAge(url: url, c: c)
        case .kind:              return checkKind(url: url, c: c)
        case .script:            return checkScript(url: url, c: c)
        case .tags:              return checkTags(url: url, c: c)
        case .colorLabel:        return checkColorLabel(url: url, c: c)
        case .comment:           return checkComment(url: url, c: c)
        case .locked:            return checkLocked(url: url, c: c)
        case .contents:          return checkContents(url: url, c: c)
        case .sourceURL:         return checkSourceURL(url: url, c: c)
        case .subfolderDepth:    return checkDepth(url: url, c: c)
        case .subItemCount:      return checkItemCount(url: url, c: c)
        case .anyFile:           return true
        case .currentTime:       return checkCurrentTime(c: c)
        case .passesAppleScript: return checkAppleScript(url: url, c: c)
        case .passesJavaScript:  return checkJavaScript(url: url, c: c)
        }
    }

    private func checkName(url: URL, c: Condition) -> Bool {
        let name = url.lastPathComponent
        if let p = c.glob,    !globMatch(pattern: p, name: name) { return false }
        if let p = c.notGlob,  globMatch(pattern: p, name: name) { return false }
        if let r = c.regex,   !regexMatch(r, in: name)           { return false }
        if let e = c.equals,      name.lowercased() != e.lowercased()         { return false }
        if let s = c.contains,   !name.localizedCaseInsensitiveContains(s)    { return false }
        if let p = c.startsWith, !name.lowercased().hasPrefix(p.lowercased()) { return false }
        if let s = c.endsWith,   !name.lowercased().hasSuffix(s.lowercased()) { return false }
        return true
    }

    private func checkExtension(url: URL, c: Condition) -> Bool {
        let ext = url.pathExtension.lowercased()
        if let e = c.equals,    ext != e.lowercased()                                  { return false }
        if let l = c.oneOf,    !l.map({$0.lowercased()}).contains(ext)                 { return false }
        if let e = c.not,       ext == e.lowercased()                                  { return false }
        if let l = c.notOneOf,  l.map({$0.lowercased()}).contains(ext)                 { return false }
        return true
    }

    private func checkSize(url: URL, c: Condition) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64 else { return false }
        if let s = c.gt,  let b = parseBytes(s), size <= b { return false }
        if let s = c.lt,  let b = parseBytes(s), size >= b { return false }
        if let s = c.gte, let b = parseBytes(s), size <  b { return false }
        if let s = c.lte, let b = parseBytes(s), size >  b { return false }
        return true
    }

    private func checkAge(url: URL, c: Condition) -> Bool {
        let key: FileAttributeKey = (c.basis ?? .modified) == .created ? .creationDate : .modificationDate
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attrs[key] as? Date else { return false }
        let age = Date().timeIntervalSince(date)  // positive = past, negative = future
        if let s = c.olderThan,    let n = parseDurationSeconds(s), age < n  { return false }
        if let s = c.newerThan,    let n = parseDurationSeconds(s), age > n  { return false }
        if let s = c.inTheNext,    let n = parseDurationSeconds(s), age > -n { return false }  // must be within next n
        if let s = c.notInTheNext, let n = parseDurationSeconds(s), age < 0 && age >= -n { return false }
        if let iso = c.beforeDate, let d = parseISODate(iso), date >= d      { return false }
        if let iso = c.afterDate,  let d = parseISODate(iso), date <= d      { return false }
        // Date exists past the guard above; `is_blank: true` cannot match here.
        if c.isBlank == true { return false }
        if let atT = c.atTime, !matchesTimeOfDay(date: date, timeStr: atT, mode: .equals)  { return false }
        if let bT  = c.beforeTime, !matchesTimeOfDay(date: date, timeStr: bT, mode: .before) { return false }
        if let aT  = c.afterTime,  !matchesTimeOfDay(date: date, timeStr: aT, mode: .after)  { return false }
        return true
    }

    private enum TimeMode { case equals, before, after }
    private func matchesTimeOfDay(date: Date, timeStr: String, mode: TimeMode) -> Bool {
        let parts = timeStr.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return false }
        let cal = Calendar.current
        let fileH = cal.component(.hour, from: date)
        let fileM = cal.component(.minute, from: date)
        let fileTotal = fileH * 60 + fileM
        let target = parts[0] * 60 + parts[1]
        switch mode {
        case .equals: return abs(fileTotal - target) <= 1
        case .before: return fileTotal < target
        case .after:  return fileTotal > target
        }
    }

    private func parseISODate(_ s: String) -> Date? {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: s)
    }

    private func checkFullName(url: URL, c: Condition) -> Bool {
        let name = url.lastPathComponent
        if let p = c.glob,    !globMatch(pattern: p, name: name) { return false }
        if let p = c.notGlob,  globMatch(pattern: p, name: name) { return false }
        if let r = c.regex,   !regexMatch(r, in: name)           { return false }
        if let e = c.equals,      name.lowercased() != e.lowercased()         { return false }
        if let s = c.contains,   !name.localizedCaseInsensitiveContains(s)    { return false }
        if let p = c.startsWith, !name.lowercased().hasPrefix(p.lowercased()) { return false }
        if let s = c.endsWith,   !name.lowercased().hasSuffix(s.lowercased()) { return false }
        if let l = c.oneOf,     !l.map({$0.lowercased()}).contains(name.lowercased()) { return false }
        if let l = c.notOneOf,   l.map({$0.lowercased()}).contains(name.lowercased()) { return false }
        if c.isBlank == true  { return name.isEmpty }
        if c.isBlank == false { return !name.isEmpty }
        return true
    }

    private func checkColorLabel(url: URL, c: Condition) -> Bool {
        guard let target = c.colorLabelValue else { return true }
        let script = "tell app \"Finder\" to get label index of (POSIX file \"\(url.path)\" as alias)"
        let result = runAppleScript(script, captureOutput: true)
        let idx = Int(result.output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        return idx == target
    }

    private func checkComment(url: URL, c: Condition) -> Bool {
        let result = runProcess("/usr/bin/mdls",
                                args: ["-name", "kMDItemFinderComment", "-raw", url.path],
                                captureOutput: true)
        let comment = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        if c.isBlank == true  { return comment.isEmpty || comment == "(null)" }
        if c.isBlank == false { return !comment.isEmpty && comment != "(null)" }
        if let s = c.contains,   !comment.localizedCaseInsensitiveContains(s)   { return false }
        if let s = c.equals,      comment.lowercased() != s.lowercased()        { return false }
        if let p = c.startsWith, !comment.lowercased().hasPrefix(p.lowercased()) { return false }
        if let s = c.endsWith,   !comment.lowercased().hasSuffix(s.lowercased()) { return false }
        return true
    }

    private func checkLocked(url: URL, c: Condition) -> Bool {
        guard let expected = c.locked else { return true }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let immutable = attrs[.immutable] as? Bool else { return false }
        return immutable == expected
    }

    private func checkContents(url: URL, c: Condition) -> Bool {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return false }
        if let s = c.contains, !text.localizedCaseInsensitiveContains(s) { return false }
        if let r = c.regex, !regexMatch(r, in: text) { return false }
        if c.isBlank == true  { return text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if c.isBlank == false { return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return true
    }

    private func checkSourceURL(url: URL, c: Condition) -> Bool {
        let sources = sourceURLs(forFile: url.path)
        if c.isBlank == true  { return sources.isEmpty }
        if c.isBlank == false { return !sources.isEmpty }
        let joined = sources.joined(separator: " ")
        if let s = c.contains,   !joined.localizedCaseInsensitiveContains(s) { return false }
        if let s = c.startsWith, !sources.contains(where: { $0.lowercased().hasPrefix(s.lowercased()) }) { return false }
        if let s = c.equals,     !sources.contains(where: { $0 == s }) { return false }
        return true
    }

    private func checkDepth(url: URL, c: Condition) -> Bool {
        guard let base = config.watch.first(where: { url.path.hasPrefix(($0.path as NSString).expandingTildeInPath) }) else { return false }
        let basePath = (base.path as NSString).expandingTildeInPath
        let relative = url.path.dropFirst(basePath.count)
        let depth = relative.split(separator: "/").count
        if let d = c.depth { return depth == d }
        if let s = c.gt,  let n = UInt64(s) { if UInt64(depth) <= n { return false } }
        if let s = c.lt,  let n = UInt64(s) { if UInt64(depth) >= n { return false } }
        if let s = c.gte, let n = UInt64(s) { if UInt64(depth) < n  { return false } }
        if let s = c.lte, let n = UInt64(s) { if UInt64(depth) > n  { return false } }
        return true
    }

    private func checkItemCount(url: URL, c: Condition) -> Bool {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
        let count = (try? FileManager.default.contentsOfDirectory(atPath: url.path))?.count ?? 0
        if let fc = c.fileCount { return count == fc }
        if let s = c.gt,  let n = UInt64(s) { if UInt64(count) <= n { return false } }
        if let s = c.lt,  let n = UInt64(s) { if UInt64(count) >= n { return false } }
        if let s = c.gte, let n = UInt64(s) { if UInt64(count) < n  { return false } }
        if let s = c.lte, let n = UInt64(s) { if UInt64(count) > n  { return false } }
        return true
    }

    private func checkCurrentTime(c: Condition) -> Bool {
        let now = Date()
        if let atT = c.atTime,    !matchesTimeOfDay(date: now, timeStr: atT, mode: .equals)  { return false }
        if let bT  = c.beforeTime, !matchesTimeOfDay(date: now, timeStr: bT, mode: .before)  { return false }
        if let aT  = c.afterTime,  !matchesTimeOfDay(date: now, timeStr: aT, mode: .after)   { return false }
        if let s = c.inTheNext, let n = parseDurationSeconds(s) {
            let futureDate = now.addingTimeInterval(n)
            _ = futureDate  // "current time is in the next N" — always true if n > 0
            return true
        }
        return true
    }

    private func checkAppleScript(url: URL, c: Condition) -> Bool {
        guard let script = c.run else { return false }
        let env = ProcessInfo.processInfo.environment.merging(["DOUMI_FILE": url.path]) { $1 }
        return runAppleScript(script, env: env).status == 0
    }

    private func checkJavaScript(url: URL, c: Condition) -> Bool {
        guard let script = c.run else { return false }
        let env = ProcessInfo.processInfo.environment.merging(["DOUMI_FILE": url.path]) { $1 }
        return runJXA(script, env: env).status == 0
    }

    private func checkKind(url: URL, c: Condition) -> Bool {
        guard let kind = c.equals else { return true }
        guard let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return false }
        switch kind.lowercased() {
        case "file":                return vals.isDirectory == false && vals.isSymbolicLink == false
        case "directory", "folder": return vals.isDirectory == true
        case "symlink", "link":     return vals.isSymbolicLink == true
        default: return false
        }
    }

    private func checkScript(url: URL, c: Condition) -> Bool {
        guard let script = c.run else { return false }
        let env = ProcessInfo.processInfo.environment.merging([
            "DOUMI_FILE": url.path,
            "DOUMI_NAME": url.deletingPathExtension().lastPathComponent,
            "DOUMI_EXT":  url.pathExtension,
        ]) { $1 }
        return runProcess("/bin/sh", args: ["-c", script], env: env).status == 0
    }

    private func checkTags(url: URL, c: Condition) -> Bool {
        guard let required = c.oneOf, !required.isEmpty else { return true }
        guard let tags = try? url.resourceValues(forKeys: [.tagNamesKey]).tagNames else { return false }
        return required.allSatisfy { tags.contains($0) }
    }

    // MARK: - Actions

    private func executeActions(url: URL, rule: RuleConfig) throws {
        var cur = url
        let ctx = TemplateContext(url: cur)
        for action in rule.actions {
            if let next = try executeAction(url: cur, action: action, ctx: ctx) { cur = next }
        }
    }

    @discardableResult
    private func executeAction(url: URL, action: Action, ctx: TemplateContext) throws -> URL? {
        let fm = FileManager.default

        switch action.type {
        case .move:
            guard let tpl = action.to else { return nil }
            var dest = URL(filePath: expandPath(tpl, context: ctx))
            let destIsDir = (try? dest.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if tpl.hasSuffix("/") || destIsDir {
                dest = dest.appendingPathComponent(url.lastPathComponent)
            }
            guard let d = try resolveConflict(at: dest, strategy: action.onConflict ?? .rename) else {
                Logger.info("    skip (exists): \(dest.lastPathComponent)"); return nil
            }
            if action.createDirs ?? true { try fm.createDirectory(at: d.deletingLastPathComponent(), withIntermediateDirectories: true) }
            if dryRun { Logger.info("    [dry-run] MOVE → \(d.path)"); return nil }
            Logger.info("    MOVE → \(d.path)")
            try fm.moveItem(at: url, to: d)
            return d

        case .fileCopy:
            guard let tpl = action.to else { return nil }
            var dest = URL(filePath: expandPath(tpl, context: ctx))
            let destIsDir = (try? dest.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            if tpl.hasSuffix("/") || destIsDir {
                dest = dest.appendingPathComponent(url.lastPathComponent)
            }
            guard let d = try resolveConflict(at: dest, strategy: action.onConflict ?? .rename) else {
                Logger.info("    skip (exists): \(dest.lastPathComponent)"); return nil
            }
            if action.createDirs ?? true { try fm.createDirectory(at: d.deletingLastPathComponent(), withIntermediateDirectories: true) }
            if dryRun { Logger.info("    [dry-run] COPY → \(d.path)"); return nil }
            Logger.info("    COPY → \(d.path)")
            try fm.copyItem(at: url, to: d); return nil

        case .rename:
            guard let tpl = action.to else { return nil }
            let dest = url.deletingLastPathComponent().appendingPathComponent(expandTemplate(tpl, context: ctx))
            guard let d = try resolveConflict(at: dest, strategy: action.onConflict ?? .rename) else {
                Logger.info("    skip (exists): \(dest.lastPathComponent)"); return nil
            }
            if dryRun { Logger.info("    [dry-run] RENAME → \(d.lastPathComponent)"); return nil }
            Logger.info("    RENAME → \(d.lastPathComponent)")
            try fm.moveItem(at: url, to: d); return d

        case .trash:
            if dryRun { Logger.info("    [dry-run] TRASH"); return nil }
            Logger.info("    TRASH"); try fm.trashItem(at: url, resultingItemURL: nil); return nil

        case .delete:
            if dryRun { Logger.info("    [dry-run] DELETE"); return nil }
            Logger.info("    DELETE"); try fm.removeItem(at: url); return nil

        case .run:
            guard let cmd = action.command.map({ expandTemplate($0, context: ctx) }) else { return nil }
            if dryRun { Logger.info("    [dry-run] RUN: \(cmd)"); return nil }
            Logger.info("    RUN: \(cmd)")
            let env = ProcessInfo.processInfo.environment.merging([
                "DOUMI_FILE": url.path, "DOUMI_NAME": ctx.stem, "DOUMI_EXT": ctx.ext,
            ]) { $1 }
            let status = runProcess("/bin/sh", args: ["-c", cmd], env: env).status
            if status != 0 { Logger.warn("    command exited \(status)") }
            return nil

        case .notify:
            guard let msg = action.message.map({ expandTemplate($0, context: ctx) }) else { return nil }
            let ttl = action.title.map { expandTemplate($0, context: ctx) } ?? "Doumi"
            if dryRun { Logger.info("    [dry-run] NOTIFY: \(ttl) – \(msg)"); return nil }
            let esc = msg.replacingOccurrences(of: "\"", with: "\\\"")
            let te  = ttl.replacingOccurrences(of: "\"", with: "\\\"")
            runAppleScript("display notification \"\(esc)\" with title \"\(te)\"")
            return nil

        case .log:
            let msg = action.message.map { expandTemplate($0, context: ctx) } ?? "Processed: \(url.path)"
            Logger.info("    LOG: \(msg)"); return nil

        case .openWith:
            if dryRun { Logger.info("    [dry-run] OPEN"); return nil }
            let args = action.with.map { ["-a", $0, url.path] } ?? [url.path]
            runProcess("/usr/bin/open", args: args)
            return nil

        case .removeTags:
            guard let tags = action.message else { return nil }
            if dryRun { Logger.info("    [dry-run] REMOVE TAGS: \(tags)"); return nil }
            let tagArg = tags.split(separator: ",")
                .map { "'\($0.trimmingCharacters(in: .whitespaces))'" }
                .joined(separator: " ")
            runProcess("/bin/sh", args: ["-c", "tag --remove \(tagArg) \"\(url.path)\" 2>/dev/null || true"])
            return nil

        case .addComment:
            guard let comment = action.message.map({ expandTemplate($0, context: ctx) }) else { return nil }
            if dryRun { Logger.info("    [dry-run] ADD COMMENT: \(comment)"); return nil }
            let esc = comment.replacingOccurrences(of: "\"", with: "\\\"")
            runAppleScript("tell app \"Finder\" to set comment of (POSIX file \"\(url.path)\" as alias) to \"\(esc)\"")
            return nil

        case .toggleExtension:
            if dryRun { Logger.info("    [dry-run] TOGGLE EXTENSION"); return nil }
            runAppleScript("""
                tell app "Finder" to set extension hidden of (POSIX file "\(url.path)" as alias) \
                to not (extension hidden of (POSIX file "\(url.path)" as alias))
                """)
            return nil

        case .toggleLock:
            if dryRun { Logger.info("    [dry-run] TOGGLE LOCK"); return nil }
            let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
            let isLocked = attrs?[.immutable] as? Bool ?? false
            try FileManager.default.setAttributes([.immutable: !isLocked], ofItemAtPath: url.path)
            return nil

        case .archive:
            if dryRun { Logger.info("    [dry-run] ARCHIVE"); return nil }
            let dest = action.to.map { expandPath($0, context: ctx) } ?? url.deletingLastPathComponent().path
            let zipName = "\(url.deletingPathExtension().lastPathComponent).zip"
            let zipPath = "\(dest)/\(zipName)"
            runProcess("/usr/bin/ditto", args: ["-c", "-k", "--keepParent", url.path, zipPath])
            Logger.info("    ARCHIVE → \(zipPath)"); return nil

        case .unarchive:
            if dryRun { Logger.info("    [dry-run] UNARCHIVE"); return nil }
            let dest = action.to.map { expandPath($0, context: ctx) } ?? url.deletingLastPathComponent().path
            runProcess("/usr/bin/ditto", args: ["-x", "-k", url.path, dest])
            Logger.info("    UNARCHIVE → \(dest)"); return nil

        case .importMusic:
            if dryRun { Logger.info("    [dry-run] IMPORT MUSIC"); return nil }
            runAppleScript("tell app \"Music\" to add POSIX file \"\(url.path)\"")
            return nil

        case .importPhotos:
            if dryRun { Logger.info("    [dry-run] IMPORT PHOTOS"); return nil }
            runAppleScript("tell app \"Photos\" to import {POSIX file \"\(url.path)\"}")
            return nil

        case .importTV:
            if dryRun { Logger.info("    [dry-run] IMPORT TV"); return nil }
            runAppleScript("tell app \"TV\" to add POSIX file \"\(url.path)\"")
            return nil

        case .runJavaScript:
            guard let script = action.command.map({ expandTemplate($0, context: ctx) }) else { return nil }
            if dryRun { Logger.info("    [dry-run] RUN JS"); return nil }
            let env = ProcessInfo.processInfo.environment.merging(["DOUMI_FILE": url.path]) { $1 }
            runJXA(script, env: env)
            return nil

        case .runAutomator:
            guard let wf = action.command else { return nil }
            if dryRun { Logger.info("    [dry-run] RUN AUTOMATOR: \(wf)"); return nil }
            runProcess("/usr/bin/automator", args: ["-i", url.path, wf])
            return nil

        case .continueMatching:
            return nil  // handled at rule level via stop=false
        }
    }

    private func resolveConflict(at dest: URL, strategy: ConflictStrategy) throws -> URL? {
        guard FileManager.default.fileExists(atPath: dest.path) else { return dest }
        switch strategy {
        case .overwrite: return dest
        case .skip:      return nil
        case .error:     throw DoumiError.destinationExists(dest)
        case .rename:
            let stem = dest.deletingPathExtension().lastPathComponent
            let ext  = dest.pathExtension
            let dir  = dest.deletingLastPathComponent()
            for i in 1...9_999 {
                let name = ext.isEmpty ? "\(stem)_\(i)" : "\(stem)_\(i).\(ext)"
                let c = dir.appendingPathComponent(name)
                if !FileManager.default.fileExists(atPath: c.path) { return c }
            }
            throw DoumiError.tooManyConflicts(dest)
        }
    }
}

// MARK: - Parsers

public func parseBytes(_ s: String) -> UInt64? {
    let s = s.trimmingCharacters(in: .whitespaces).lowercased()
    guard let i = s.firstIndex(where: { $0.isLetter }) else { return UInt64(s) }
    guard let n = Double(s[s.startIndex..<i].trimmingCharacters(in: .whitespaces)) else { return nil }
    let mul: UInt64
    switch String(s[i...]).trimmingCharacters(in: .whitespaces) {
    case "b","": mul=1; case "k","kb": mul=1_024; case "m","mb": mul=1_048_576
    case "g","gb": mul=1_073_741_824; case "t","tb": mul=1_099_511_627_776; default: return nil
    }
    return UInt64(n * Double(mul))
}

public func parseDurationSeconds(_ s: String) -> Double? {
    let s = s.trimmingCharacters(in: .whitespaces).lowercased()
    guard let i = s.firstIndex(where: { $0.isLetter }) else { return Double(s) }
    guard let n = Double(s[s.startIndex..<i].trimmingCharacters(in: .whitespaces)) else { return nil }
    switch String(s[i...]).trimmingCharacters(in: .whitespaces) {
    case "s","sec","second","seconds": return n
    case "m","min","minute","minutes": return n*60
    case "h","hr","hour","hours":      return n*3_600
    case "d","day","days":             return n*86_400
    case "w","wk","week","weeks":      return n*86_400*7
    case "mo","month","months":        return n*86_400*30
    case "y","yr","year","years":      return n*86_400*365
    default: return nil
    }
}

// MARK: - Process / shell helpers

@discardableResult
func runProcess(
    _ executablePath: String,
    args: [String],
    env: [String: String]? = nil,
    captureOutput: Bool = false
) -> (status: Int32, output: String) {
    let p = Process()
    p.executableURL = URL(filePath: executablePath)
    p.arguments = args
    if let env { p.environment = env }
    var outPipe: Pipe?
    if captureOutput {
        let o = Pipe()
        outPipe = o
        p.standardOutput = o
        p.standardError = Pipe() // discard stderr
    }
    do { try p.run() } catch { return (-1, "") }
    p.waitUntilExit()
    let output: String
    if let outPipe {
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        output = String(data: data, encoding: .utf8) ?? ""
    } else {
        output = ""
    }
    return (p.terminationStatus, output)
}

@discardableResult
func runAppleScript(_ source: String, env: [String: String]? = nil, captureOutput: Bool = false) -> (status: Int32, output: String) {
    runProcess("/usr/bin/osascript", args: ["-e", source], env: env, captureOutput: captureOutput)
}

@discardableResult
func runJXA(_ source: String, env: [String: String]? = nil, captureOutput: Bool = false) -> (status: Int32, output: String) {
    runProcess("/usr/bin/osascript", args: ["-l", "JavaScript", "-e", source], env: env, captureOutput: captureOutput)
}

// MARK: - Glob matching

/// Case-insensitive glob via `fnmatch(3)`, matching the prior `LIKE[c]` semantics.
func globMatch(pattern: String, name: String) -> Bool {
    name.withCString { nptr in
        pattern.withCString { pptr in
            fnmatch(pptr, nptr, FNM_CASEFOLD) == 0
        }
    }
}

// MARK: - Regex helper

func regexMatch(_ pattern: String, in text: String) -> Bool {
    guard let r = try? Regex(pattern) else { return false }
    return text.contains(r)
}

// MARK: - Spotlight "Where From" via getxattr

/// Reads `kMDItemWhereFroms` directly via `getxattr` and decodes the binary plist.
func sourceURLs(forFile path: String) -> [String] {
    let attrName = "com.apple.metadata:kMDItemWhereFroms"
    let size: Int = path.withCString { pp in
        attrName.withCString { ap in getxattr(pp, ap, nil, 0, 0, 0) }
    }
    guard size > 0 else { return [] }
    var buffer = [UInt8](repeating: 0, count: size)
    let read: Int = buffer.withUnsafeMutableBytes { raw in
        guard let base = raw.baseAddress else { return -1 }
        return path.withCString { pp in
            attrName.withCString { ap in getxattr(pp, ap, base, size, 0, 0) }
        }
    }
    guard read > 0 else { return [] }
    let data = Data(buffer.prefix(read))
    let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    return (plist as? [String]) ?? []
}
