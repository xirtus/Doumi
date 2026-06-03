import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DoumiCore

// MARK: - Condition field enum (all Hazel-parity fields)

enum ConditionField: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case name            = "Name"
    case fullName        = "Full Name"
    case ext             = "Extension"
    case dateAdded       = "Date Added"
    case dateCreated     = "Date Created"
    case dateModified    = "Date Last Modified"
    case dateLastOpened  = "Date Last Opened"
    case currentTime     = "Current Time"
    case kind            = "Kind"
    case tags            = "Tags"
    case colorLabel      = "Color Label"
    case comment         = "Comment"
    case size            = "Size"
    case locked          = "Locked"
    case contents        = "Contents"
    case sourceURL       = "Source URL / Address"
    case subfolderDepth  = "Subfolder Depth"
    case subItemCount    = "Sub-item Count"
    case anyFile         = "Any File"
    case passesAppleScript = "Passes AppleScript"
    case passesJavaScript  = "Passes JavaScript"
    case shellScript       = "Passes shell script"
}

// MARK: - Operators

enum NameOp: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case contains       = "contains"
    case doesNotContain = "does not contain"
    case startsWith     = "starts with"
    case endsWith       = "ends with"
    case is_            = "is"
    case isNot          = "is not"
    case matchesGlob    = "matches"
    case doesNotMatch   = "does not match"
    case matchesRegex   = "matches regex"
    case isAmong        = "is among"
    case isNotAmong     = "is not among"
    case isBlank        = "is blank"
    case isNotBlank     = "is not blank"
}

enum DateOp: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case isInTheLast    = "is in the last"
    case isNotInTheLast = "is not in the last"
    case isInTheNext    = "is in the next"
    case isNotInTheNext = "is not in the next"
    case isOlderThan    = "is older than"
    case isNewerThan    = "is newer than"
    case isBefore       = "is before"
    case isAfter        = "is after"
    case occursAt       = "occurs at"
    case occursBefore   = "occurs before"
    case occursAfter    = "occurs after"
    case didChange      = "did change"
    case didNotChange   = "did not change"
    case isBlank        = "is blank"
    case isNotBlank     = "is not blank"

    var usesRelativeTime: Bool {
        switch self {
        case .isInTheLast, .isNotInTheLast, .isInTheNext, .isNotInTheNext, .isOlderThan, .isNewerThan: return true
        default: return false
        }
    }
    var usesAbsoluteDate: Bool { self == .isBefore || self == .isAfter }
    var usesTimeOfDay: Bool { self == .occursAt || self == .occursBefore || self == .occursAfter }
    var usesNoValue: Bool { self == .didChange || self == .didNotChange || self == .isBlank || self == .isNotBlank }
}

enum DateUnit: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case minutes = "Minutes"
    case hours   = "Hours"
    case days    = "Days"
    case weeks   = "Weeks"
    case months  = "Months"
    case years   = "Years"
    var suffix: String {
        switch self {
        case .minutes: "m"; case .hours: "h"; case .days: "d"
        case .weeks: "w"; case .months: "mo"; case .years: "y"
        }
    }
}

enum SizeCmp: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case greaterThan = "is greater than"
    case lessThan    = "is less than"
    case atLeast     = "is at least"
    case atMost      = "is at most"
    case exactly     = "is exactly"
}

enum SizeUnit: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case bytes = "bytes"; case kb = "KB"; case mb = "MB"; case gb = "GB"
    var yamlSuffix: String {
        switch self { case .bytes: "b"; case .kb: "KB"; case .mb: "MB"; case .gb: "GB" }
    }
}

enum ExtOp: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case is_        = "is"
    case isNot      = "is not"
    case isOneOf    = "is one of"
    case isNotOneOf = "is not one of"
}

enum KindOpt: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case file = "file"; case folder = "folder"; case alias = "alias"
}

enum NumericOp: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case equals      = "is"
    case greaterThan = "is greater than"
    case lessThan    = "is less than"
    case atLeast     = "is at least"
    case atMost      = "is at most"
}

// MARK: - Condition Draft

struct ConditionDraft: Identifiable {
    var id = UUID()
    var field: ConditionField = .name
    // name / text fields
    var nameOp: NameOp = .contains
    var nameValue: String = ""
    var nameListValue: String = ""   // newline-separated for isAmong
    // extension
    var extOp: ExtOp = .is_
    var extValue: String = ""
    // date (relative)
    var dateOp: DateOp = .isInTheLast
    var dateValue: Int = 7
    var dateUnit: DateUnit = .days
    // date (absolute)
    var absoluteDate: Date = Date()
    // time of day
    var timeOfDay: Date = Calendar.current.date(from: DateComponents(hour: 9, minute: 0)) ?? Date()
    // size
    var sizeCmp: SizeCmp = .greaterThan
    var sizeValue: Int = 1
    var sizeUnit: SizeUnit = .mb
    // kind
    var kindIsNot: Bool = false
    var kindValue: KindOpt = .file
    // locked
    var lockedValue: Bool = true
    // color label
    var condColorLabel: ColorLabel = .none
    var colorIsNot: Bool = false
    // numeric (depth, count)
    var numericOp: NumericOp = .greaterThan
    var numericValue: Int = 0
    // scripts
    var scriptValue: String = ""

    func toCondition() -> Condition? {
        switch field {
        case .name, .fullName:
            var c = Condition(type: field == .fullName ? .fullName : .name)
            switch nameOp {
            case .contains:       c.contains   = orNil(nameValue)
            case .doesNotContain: c.notGlob    = orNil(nameValue).map { "*\($0)*" }
            case .startsWith:     c.startsWith = orNil(nameValue)
            case .endsWith:       c.endsWith   = orNil(nameValue)
            case .is_:            c.equals     = orNil(nameValue)
            case .isNot:          c.notGlob    = orNil(nameValue)
            case .matchesGlob:    c.glob       = orNil(nameValue)
            case .doesNotMatch:   c.notGlob    = orNil(nameValue)
            case .matchesRegex:   c.regex      = orNil(nameValue)
            case .isAmong:
                let parts = nameListValue.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                c.oneOf = parts.isEmpty ? nil : parts
            case .isNotAmong:
                let parts = nameListValue.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                c.notOneOf = parts.isEmpty ? nil : parts
            case .isBlank:    c.isBlank = true
            case .isNotBlank: c.isBlank = false
            }
            return c

        case .ext:
            var c = Condition(type: .ext)
            let parts = extValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            switch extOp {
            case .is_:        c.equals   = parts.first
            case .isNot:      c.not      = parts.first
            case .isOneOf:    c.oneOf    = parts.isEmpty ? nil : parts
            case .isNotOneOf: c.notOneOf = parts.isEmpty ? nil : parts
            }
            return c

        case .dateAdded, .dateCreated, .dateModified, .dateLastOpened, .currentTime:
            let condType: ConditionType = field == .currentTime ? .currentTime : .age
            var c = Condition(type: condType)
            if field == .dateCreated { c.basis = .created }
            else if field != .currentTime { c.basis = .modified }
            let val = "\(dateValue)\(dateUnit.suffix)"
            switch dateOp {
            case .isInTheLast:    c.newerThan     = val
            case .isNotInTheLast: c.olderThan     = val
            case .isInTheNext:    c.inTheNext     = val
            case .isNotInTheNext: c.notInTheNext  = val
            case .isOlderThan:    c.olderThan     = val
            case .isNewerThan:    c.newerThan     = val
            case .isBefore:
                let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
                c.beforeDate = fmt.string(from: absoluteDate)
            case .isAfter:
                let fmt = DateFormatter(); fmt.dateFormat = "yyyy-MM-dd"
                c.afterDate = fmt.string(from: absoluteDate)
            case .occursAt:
                let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
                c.atTime = fmt.string(from: timeOfDay)
            case .occursBefore:
                let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
                c.beforeTime = fmt.string(from: timeOfDay)
            case .occursAfter:
                let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
                c.afterTime = fmt.string(from: timeOfDay)
            case .didChange:    c.didChange = true
            case .didNotChange: c.didChange = false
            case .isBlank:      c.isBlank = true
            case .isNotBlank:   c.isBlank = false
            }
            return c

        case .size:
            var c = Condition(type: .size)
            let val = "\(sizeValue)\(sizeUnit.yamlSuffix)"
            switch sizeCmp {
            case .greaterThan: c.gt  = val
            case .lessThan:    c.lt  = val
            case .atLeast:     c.gte = val
            case .atMost:      c.lte = val
            case .exactly:     c.gte = val; c.lte = val
            }
            return c

        case .kind:
            var c = Condition(type: .kind)
            c.equals = kindIsNot ? nil : kindValue.rawValue
            if kindIsNot {
                // Approximate by notGlob on empty (engine: kind "is not" not directly supported)
                c.equals = kindValue.rawValue  // TODO: engine support for kind negation
            }
            return c

        case .tags:
            var c = Condition(type: .tags)
            let parts = nameValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            c.oneOf = parts.isEmpty ? nil : parts
            return c

        case .colorLabel:
            var c = Condition(type: .colorLabel)
            c.colorLabelValue = condColorLabel.finderIndex
            return c

        case .comment:
            var c = Condition(type: .comment)
            switch nameOp {
            case .contains:       c.contains   = orNil(nameValue)
            case .doesNotContain: c.notGlob    = orNil(nameValue).map { "*\($0)*" }
            case .startsWith:     c.startsWith = orNil(nameValue)
            case .endsWith:       c.endsWith   = orNil(nameValue)
            case .is_:            c.equals     = orNil(nameValue)
            case .isNot:          c.notGlob    = orNil(nameValue)
            case .isBlank:        c.isBlank = true
            case .isNotBlank:     c.isBlank = false
            default:              c.contains = orNil(nameValue)
            }
            return c

        case .locked:
            var c = Condition(type: .locked)
            c.locked = lockedValue
            return c

        case .contents:
            var c = Condition(type: .contents)
            switch nameOp {
            case .contains:      c.contains = orNil(nameValue)
            case .matchesRegex:  c.regex    = orNil(nameValue)
            case .isBlank:       c.isBlank  = true
            case .isNotBlank:    c.isBlank  = false
            default:             c.contains = orNil(nameValue)
            }
            return c

        case .sourceURL:
            var c = Condition(type: .sourceURL)
            switch nameOp {
            case .contains:      c.contains   = orNil(nameValue)
            case .startsWith:    c.startsWith = orNil(nameValue)
            case .endsWith:      c.endsWith   = orNil(nameValue)
            case .is_:           c.equals     = orNil(nameValue)
            case .isBlank:       c.isBlank    = true
            case .isNotBlank:    c.isBlank    = false
            default:             c.contains   = orNil(nameValue)
            }
            return c

        case .subfolderDepth:
            var c = Condition(type: .subfolderDepth)
            applyNumeric(to: &c)
            return c

        case .subItemCount:
            var c = Condition(type: .subItemCount)
            applyNumeric(to: &c)
            return c

        case .anyFile:
            return Condition(type: .anyFile)

        case .passesAppleScript:
            var c = Condition(type: .passesAppleScript)
            c.run = scriptValue.isEmpty ? nil : scriptValue
            return c

        case .passesJavaScript:
            var c = Condition(type: .passesJavaScript)
            c.run = scriptValue.isEmpty ? nil : scriptValue
            return c

        case .shellScript:
            var c = Condition(type: .script)
            c.run = scriptValue.isEmpty ? nil : scriptValue
            return c
        }
    }

    private func orNil(_ s: String) -> String? { s.isEmpty ? nil : s }

    private func applyNumeric(to c: inout Condition) {
        let val = String(numericValue)
        switch numericOp {
        case .equals:      c.depth = numericValue; c.fileCount = numericValue
        case .greaterThan: c.gt = val
        case .lessThan:    c.lt = val
        case .atLeast:     c.gte = val
        case .atMost:      c.lte = val
        }
    }
}

// MARK: - Action Draft

enum ActionDraftType: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    // File
    case move              = "Move"
    case copy              = "Copy"
    case rename            = "Rename"
    case sortIntoSubfolder = "Sort into subfolder"
    case trash             = "Move to Trash"
    case delete            = "Delete"
    case archive           = "Archive (zip)"
    case unarchive         = "Unarchive"
    case makeAlias         = "Make alias"
    // Metadata
    case addTags           = "Add tags"
    case removeTags        = "Remove tags"
    case setColorLabel     = "Set color label"
    case addComment        = "Add comment"
    case toggleExtension   = "Toggle extension"
    case toggleLock        = "Toggle lock"
    // Open / Reveal
    case openWith          = "Open"
    case showInFinder      = "Show in Finder"
    // Import
    case importMusic       = "Import into Music"
    case importPhotos      = "Import into Photos"
    case importTV          = "Import into TV"
    // Notify / Log
    case notify            = "Display notification"
    case log               = "Log"
    // Scripts
    case runShellScript    = "Run shell script"
    case runAppleScript    = "Run AppleScript"
    case runJavaScript     = "Run JavaScript"
    case runAutomator      = "Run Automator workflow"
    case runShortcut       = "Run Shortcut"
    // Flow
    case continueMatching  = "Continue matching rules"
    case ignore            = "Ignore"
}

enum ColorLabel: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case none = "None"; case gray = "Gray"; case green = "Green"; case purple = "Purple"
    case blue = "Blue"; case yellow = "Yellow"; case red = "Red"; case orange = "Orange"
    var labelColor: Color {
        switch self {
        case .none: return Color(NSColor.controlBackgroundColor)
        case .gray: return .gray; case .green: return .green; case .purple: return .purple
        case .blue: return .blue; case .yellow: return .yellow; case .red: return .red
        case .orange: return .orange
        }
    }
    var finderIndex: Int {
        switch self { case .none:0; case .gray:1; case .green:2; case .purple:3
                      case .blue:4; case .yellow:5; case .red:6; case .orange:7 }
    }
    static func from(index: Int) -> ColorLabel {
        allCases.first { $0.finderIndex == index } ?? .none
    }
}

enum SortMode: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case yearMonth = "Year / Month"
    case year      = "Year"
    case ext       = "Extension"
    case custom    = "Custom pattern"
    func pattern(base: String) -> String {
        let b = base.isEmpty ? "~" : base
        switch self {
        case .yearMonth: return "\(b)/{year}/{month}/"
        case .year:      return "\(b)/{year}/"
        case .ext:       return "\(b)/{ext}/"
        case .custom:    return b + "/"
        }
    }
}

struct ActionDraft: Identifiable {
    var id = UUID()
    var type: ActionDraftType = .move
    var destination: String = ""
    var onConflict: ConflictStrategy = .rename
    var createDirs: Bool = true
    var renameTo: String = "{name}.{ext}"
    var sortBase: String = ""
    var sortMode: SortMode = .yearMonth
    var sortCustomPattern: String = "{year}/{month}"
    var command: String = ""
    var notifTitle: String = "Doumi"
    var notifMessage: String = "Processed {name}"
    var openWithApp: String = ""
    var aliasDestination: String = ""
    var tagsValue: String = ""
    var colorLabel: ColorLabel = .none
    var logMessage: String = "{filename}"
    var shortcutName: String = ""
    var commentText: String = ""

    func toAction() -> Action? {
        switch type {
        case .move:
            var a = Action(type: .move)
            a.to = destination.isEmpty ? nil : destination
            a.onConflict = onConflict; a.createDirs = createDirs; return a
        case .copy:
            var a = Action(type: .fileCopy)
            a.to = destination.isEmpty ? nil : destination
            a.onConflict = onConflict; a.createDirs = createDirs; return a
        case .rename:
            var a = Action(type: .rename)
            a.to = renameTo.isEmpty ? nil : renameTo; return a
        case .sortIntoSubfolder:
            var a = Action(type: .move)
            let pattern = sortMode == .custom
                ? "\(sortBase.isEmpty ? "~" : sortBase)/\(sortCustomPattern)/"
                : sortMode.pattern(base: sortBase)
            a.to = pattern; a.createDirs = true; a.onConflict = onConflict; return a
        case .trash:  return Action(type: .trash)
        case .delete: return Action(type: .delete)
        case .archive:
            var a = Action(type: .archive)
            a.to = destination.isEmpty ? nil : destination; return a
        case .unarchive:
            var a = Action(type: .unarchive)
            a.to = destination.isEmpty ? nil : destination; return a
        case .makeAlias:
            var a = Action(type: .run)
            let dest = aliasDestination.isEmpty ? "~/Desktop" : aliasDestination
            a.command = "ln -s \"$DOUMI_FILE\" \"\(dest)/$(basename \"$DOUMI_FILE\")\""
            return a
        case .addTags:
            var a = Action(type: .run)
            let tags = tagsValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.map { "'\($0)'" }.joined(separator: " ")
            a.command = "tag --add \(tags) \"$DOUMI_FILE\" 2>/dev/null || true"; return a
        case .removeTags:
            var a = Action(type: .removeTags)
            a.message = tagsValue.isEmpty ? nil : tagsValue; return a
        case .setColorLabel:
            var a = Action(type: .run)
            a.command = "osascript -e 'tell app \"Finder\" to set label index of (POSIX file \"'\"$DOUMI_FILE\"'\" as alias) to \(colorLabel.finderIndex)'"
            return a
        case .addComment:
            var a = Action(type: .addComment)
            a.message = commentText.isEmpty ? nil : commentText; return a
        case .toggleExtension:
            return Action(type: .toggleExtension)
        case .toggleLock:
            return Action(type: .toggleLock)
        case .openWith:
            var a = Action(type: .openWith)
            a.with = openWithApp.isEmpty ? nil : openWithApp; return a
        case .showInFinder:
            var a = Action(type: .run)
            a.command = "open -R \"$DOUMI_FILE\""; return a
        case .importMusic:   return Action(type: .importMusic)
        case .importPhotos:  return Action(type: .importPhotos)
        case .importTV:      return Action(type: .importTV)
        case .notify:
            var a = Action(type: .notify)
            a.title = notifTitle.isEmpty ? nil : notifTitle
            a.message = notifMessage.isEmpty ? nil : notifMessage; return a
        case .log:
            var a = Action(type: .log)
            a.message = logMessage.isEmpty ? nil : logMessage; return a
        case .runShellScript:
            var a = Action(type: .run)
            a.command = command.isEmpty ? nil : command; return a
        case .runAppleScript:
            var a = Action(type: .run)
            let esc = command.replacingOccurrences(of: "'", with: "'\\''")
            a.command = "osascript -e '\(esc)'"; return a
        case .runJavaScript:
            var a = Action(type: .runJavaScript)
            a.command = command.isEmpty ? nil : command; return a
        case .runAutomator:
            var a = Action(type: .runAutomator)
            a.command = command.isEmpty ? nil : command; return a
        case .runShortcut:
            var a = Action(type: .run)
            a.command = shortcutName.isEmpty ? nil : "shortcuts run \"\(shortcutName)\" --input-path \"$DOUMI_FILE\""
            return a
        case .continueMatching:
            return Action(type: .continueMatching)
        case .ignore:
            return nil
        }
    }
}

// MARK: - Rule Editor View

struct RuleEditorView: View {
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    let initialFolderPath: String?
    let onSave: (String, RuleConfig) -> Void

    @State private var folderPath: String = ""
    @State private var ruleName: String = ""
    @State private var matchMode: MatchMode = .all
    @State private var conditions: [ConditionDraft] = [ConditionDraft()]
    @State private var actions: [ActionDraft] = [ActionDraft()]
    @State private var stopAfterMatch: Bool = true

    private var suggestedFolders: [(name: String, path: String)] {
        [("Desktop","~/Desktop"),("Downloads","~/Downloads"),("Documents","~/Documents"),
         ("Pictures","~/Pictures"),("Music","~/Music"),("Movies","~/Movies"),
         ("Applications","/Applications"),("Home","~")]
        .filter { FileManager.default.fileExists(atPath: ($0.path as NSString).expandingTildeInPath) }
    }

    init(initialFolderPath: String? = nil, onSave: @escaping (String, RuleConfig) -> Void) {
        self.initialFolderPath = initialFolderPath
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection.padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 14)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    conditionsSection
                    Divider()
                    actionsSection
                }
                .padding(20)
            }
            Divider()
            footerButtons.padding(.horizontal, 20).padding(.vertical, 12)
        }
        .frame(minWidth: 720, idealWidth: 780, minHeight: 540, idealHeight: 640)
        .onAppear {
            if let p = initialFolderPath, !p.isEmpty { folderPath = p }
            else if let first = state.config.watch.first { folderPath = first.path }
            else if let first = suggestedFolders.first { folderPath = first.path }
        }
    }

    // MARK: Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("In Folder:")
                    .font(.system(size: 13, weight: .medium)).frame(width: 82, alignment: .trailing)
                Picker("", selection: $folderPath) {
                    if !state.config.watch.isEmpty {
                        Section("Watched Folders") {
                            ForEach(state.config.watch) { w in Text(shortPath(w.path)).tag(w.path) }
                        }
                    }
                    Section("Common Folders") {
                        ForEach(suggestedFolders, id: \.path) { f in Text(f.name).tag(f.path) }
                    }
                }
                .frame(width: 200).fixedSize()
                Button("Browse…") { browseFolder() }.buttonStyle(.bordered)
                Spacer()
            }
            HStack(spacing: 10) {
                Text("Rule Name:")
                    .font(.system(size: 13, weight: .medium)).frame(width: 82, alignment: .trailing)
                TextField("e.g. Archive Old Downloads", text: $ruleName).textFieldStyle(.roundedBorder)
            }
        }
    }

    // MARK: Conditions

    private var conditionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 5) {
                Text("If").font(.system(size: 13))
                Picker("", selection: $matchMode) {
                    Text("all").tag(MatchMode.all)
                    Text("any").tag(MatchMode.any)
                    Text("none").tag(MatchMode.none)
                }
                .frame(width: 72).fixedSize()
                Text("of the following conditions are met:").font(.system(size: 13))
                Spacer()
            }
            ForEach($conditions) { $cond in
                ConditionRow(draft: $cond) { removeCondition(cond.id) }
            }
            Button { withAnimation(.easeInOut(duration: 0.15)) { addCondition() } } label: {
                Label("Add Condition", systemImage: "plus.circle").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain).foregroundStyle(Color.accentColor)
        }
    }

    // MARK: Actions

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Do the following to the matched file or folder:").font(.system(size: 13))
            ForEach($actions) { $action in
                ActionRow(draft: $action) { removeAction(action.id) }
            }
            Button { withAnimation(.easeInOut(duration: 0.15)) { addAction() } } label: {
                Label("Add Action", systemImage: "plus.circle").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain).foregroundStyle(Color.accentColor)
            Toggle("Stop processing other rules after this rule matches", isOn: $stopAfterMatch)
                .toggleStyle(.checkbox).font(.caption).padding(.top, 2)
        }
    }

    // MARK: Footer

    private var footerButtons: some View {
        HStack {
            Button("Revert") { revert() }.buttonStyle(.bordered)
            Spacer()
            Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Save") { save() }.buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction).disabled(folderPath.isEmpty)
        }
    }

    private func shortPath(_ p: String) -> String {
        p.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
    private func browseFolder() {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.message = "Choose folder for this rule"; panel.prompt = "Select"
        if panel.runModal() == .OK, let url = panel.url {
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            folderPath = url.path.hasPrefix(home + "/") ? "~" + String(url.path.dropFirst(home.count)) : url.path
        }
    }
    private func addCondition() { conditions.append(ConditionDraft()) }
    private func removeCondition(_ id: UUID) {
        conditions.removeAll { $0.id == id }
        if conditions.isEmpty { conditions.append(ConditionDraft()) }
    }
    private func addAction() { actions.append(ActionDraft()) }
    private func removeAction(_ id: UUID) {
        actions.removeAll { $0.id == id }
        if actions.isEmpty { actions.append(ActionDraft()) }
    }
    private func revert() {
        ruleName = ""; matchMode = .all; stopAfterMatch = true
        conditions = [ConditionDraft()]; actions = [ActionDraft()]
    }
    private func save() {
        var rule = RuleConfig()
        rule.name = ruleName.isEmpty ? nil : ruleName
        rule.match = matchMode; rule.stop = stopAfterMatch
        rule.conditions = conditions.compactMap { $0.toCondition() }
        rule.actions = actions.compactMap { $0.toAction() }
        // "Continue matching rules" action means stop = false
        if actions.contains(where: { $0.type == .continueMatching }) { rule.stop = false }
        onSave(folderPath, rule)
        dismiss()
    }
}

// MARK: - Condition Row

private struct ConditionRow: View {
    @Binding var draft: ConditionDraft
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Picker("", selection: $draft.field) {
                        Section("Name") {
                            Text("Name").tag(ConditionField.name)
                            Text("Full Name").tag(ConditionField.fullName)
                            Text("Extension").tag(ConditionField.ext)
                        }
                        Section("Date") {
                            Text("Date Added").tag(ConditionField.dateAdded)
                            Text("Date Created").tag(ConditionField.dateCreated)
                            Text("Date Last Modified").tag(ConditionField.dateModified)
                            Text("Date Last Opened").tag(ConditionField.dateLastOpened)
                            Text("Current Time").tag(ConditionField.currentTime)
                        }
                        Section("File") {
                            Text("Kind").tag(ConditionField.kind)
                            Text("Size").tag(ConditionField.size)
                            Text("Locked").tag(ConditionField.locked)
                            Text("Contents").tag(ConditionField.contents)
                        }
                        Section("Metadata") {
                            Text("Tags").tag(ConditionField.tags)
                            Text("Color Label").tag(ConditionField.colorLabel)
                            Text("Comment").tag(ConditionField.comment)
                            Text("Source URL / Address").tag(ConditionField.sourceURL)
                        }
                        Section("Structure") {
                            Text("Subfolder Depth").tag(ConditionField.subfolderDepth)
                            Text("Sub-item Count").tag(ConditionField.subItemCount)
                            Text("Any File").tag(ConditionField.anyFile)
                        }
                        Section("Script") {
                            Text("Passes AppleScript").tag(ConditionField.passesAppleScript)
                            Text("Passes JavaScript").tag(ConditionField.passesJavaScript)
                            Text("Passes shell script").tag(ConditionField.shellScript)
                        }
                    }
                    .frame(width: 175).fixedSize()
                    .onChange(of: draft.field) { _, _ in
                        draft.nameValue = ""; draft.extValue = ""; draft.scriptValue = ""
                        draft.nameListValue = ""; draft.dateValue = 7; draft.sizeValue = 1; draft.numericValue = 0
                    }

                    operatorAndValue
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill").font(.system(size: 16)).foregroundStyle(.red.opacity(0.75))
            }
            .buttonStyle(.plain).padding(.top, 3)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
    }

    @ViewBuilder
    private var operatorAndValue: some View {
        switch draft.field {

        case .name, .fullName:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Picker("", selection: $draft.nameOp) {
                        ForEach(NameOp.allCases) { o in Text(o.rawValue).tag(o) }
                    }
                    .frame(width: 160).fixedSize()
                    if draft.nameOp != .isBlank && draft.nameOp != .isNotBlank
                        && draft.nameOp != .isAmong && draft.nameOp != .isNotAmong {
                        TextField("value", text: $draft.nameValue).textFieldStyle(.roundedBorder)
                    }
                }
                if draft.nameOp == .isAmong || draft.nameOp == .isNotAmong {
                    TextEditor(text: $draft.nameListValue)
                        .font(.system(size: 12))
                        .frame(height: 52)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
                    Text("One value per line").font(.caption2).foregroundStyle(.tertiary)
                }
            }

        case .ext:
            HStack(spacing: 6) {
                Picker("", selection: $draft.extOp) {
                    ForEach(ExtOp.allCases) { o in Text(o.rawValue).tag(o) }
                }
                .frame(width: 120).fixedSize()
                TextField(draft.extOp == .isOneOf || draft.extOp == .isNotOneOf ? "pdf, doc, txt" : "pdf",
                          text: $draft.extValue)
                    .textFieldStyle(.roundedBorder)
                    .help("Comma-separated for multiple")
            }

        case .dateAdded, .dateCreated, .dateModified, .dateLastOpened, .currentTime:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Picker("", selection: $draft.dateOp) {
                        ForEach(DateOp.allCases) { o in Text(o.rawValue).tag(o) }
                    }
                    .frame(width: 175).fixedSize()
                    if draft.dateOp.usesRelativeTime {
                        HStack(spacing: 4) {
                            TextField("", value: $draft.dateValue, format: .number)
                                .textFieldStyle(.roundedBorder).frame(width: 48)
                            Stepper("", value: $draft.dateValue, in: 1...9999).labelsHidden()
                            Picker("", selection: $draft.dateUnit) {
                                ForEach(DateUnit.allCases) { u in Text(u.rawValue).tag(u) }
                            }
                            .frame(width: 90).fixedSize()
                        }
                    }
                    if draft.dateOp.usesAbsoluteDate {
                        DatePicker("", selection: $draft.absoluteDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    if draft.dateOp.usesTimeOfDay {
                        DatePicker("", selection: $draft.timeOfDay, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
            }

        case .size:
            HStack(spacing: 6) {
                Picker("", selection: $draft.sizeCmp) {
                    ForEach(SizeCmp.allCases) { c in Text(c.rawValue).tag(c) }
                }
                .frame(width: 140).fixedSize()
                HStack(spacing: 4) {
                    TextField("", value: $draft.sizeValue, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 60)
                    Stepper("", value: $draft.sizeValue, in: 1...999999).labelsHidden()
                    Picker("", selection: $draft.sizeUnit) {
                        ForEach(SizeUnit.allCases) { u in Text(u.rawValue).tag(u) }
                    }
                    .frame(width: 70).fixedSize()
                }
            }

        case .kind:
            HStack(spacing: 6) {
                Picker("", selection: $draft.kindIsNot) {
                    Text("is").tag(false); Text("is not").tag(true)
                }
                .frame(width: 78).fixedSize()
                Picker("", selection: $draft.kindValue) {
                    ForEach(KindOpt.allCases) { k in Text(k.rawValue).tag(k) }
                }
                .frame(width: 80).fixedSize()
            }

        case .locked:
            HStack(spacing: 6) {
                Text("is").font(.system(size: 13)).foregroundStyle(.secondary)
                Picker("", selection: $draft.lockedValue) {
                    Text("locked").tag(true); Text("not locked").tag(false)
                }
                .frame(width: 110).fixedSize()
            }

        case .tags:
            HStack(spacing: 6) {
                Text("includes any of").font(.system(size: 13)).foregroundStyle(.secondary)
                TextField("work, important", text: $draft.nameValue)
                    .textFieldStyle(.roundedBorder).help("Comma-separated tag names")
            }

        case .colorLabel:
            HStack(spacing: 8) {
                Picker("", selection: $draft.colorIsNot) {
                    Text("is").tag(false); Text("is not").tag(true)
                }
                .frame(width: 78).fixedSize()
                HStack(spacing: 5) {
                    ForEach(ColorLabel.allCases) { label in
                        Button { draft.condColorLabel = label } label: {
                            Circle().fill(label.labelColor).frame(width: 20, height: 20)
                                .overlay(Circle().stroke(
                                    draft.condColorLabel == label ? Color.accentColor : Color(NSColor.separatorColor),
                                    lineWidth: draft.condColorLabel == label ? 2 : 0.5))
                        }
                        .buttonStyle(.plain).help(label.rawValue)
                    }
                }
                Text(draft.condColorLabel.rawValue).font(.caption).foregroundStyle(.secondary)
            }

        case .comment, .contents, .sourceURL:
            HStack(spacing: 6) {
                Picker("", selection: $draft.nameOp) {
                    Text("contains").tag(NameOp.contains)
                    Text("does not contain").tag(NameOp.doesNotContain)
                    Text("starts with").tag(NameOp.startsWith)
                    Text("ends with").tag(NameOp.endsWith)
                    Text("is").tag(NameOp.is_)
                    Text("is not").tag(NameOp.isNot)
                    Text("matches regex").tag(NameOp.matchesRegex)
                    Divider()
                    Text("is blank").tag(NameOp.isBlank)
                    Text("is not blank").tag(NameOp.isNotBlank)
                }
                .frame(width: 160).fixedSize()
                if draft.nameOp != .isBlank && draft.nameOp != .isNotBlank {
                    TextField("value", text: $draft.nameValue).textFieldStyle(.roundedBorder)
                }
            }

        case .subfolderDepth, .subItemCount:
            HStack(spacing: 6) {
                Picker("", selection: $draft.numericOp) {
                    ForEach(NumericOp.allCases) { o in Text(o.rawValue).tag(o) }
                }
                .frame(width: 140).fixedSize()
                HStack(spacing: 4) {
                    TextField("", value: $draft.numericValue, format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 60)
                    Stepper("", value: $draft.numericValue, in: 0...9999).labelsHidden()
                }
            }

        case .anyFile:
            Text("Matches any file or folder").font(.caption).foregroundStyle(.secondary)

        case .passesAppleScript, .passesJavaScript, .shellScript:
            let label: String = draft.field == .passesAppleScript ? "AppleScript" :
                                draft.field == .passesJavaScript  ? "JavaScript (JXA)" : "Shell script"
            VStack(alignment: .leading, spacing: 4) {
                Text("\(label) — exit 0 = condition met  •  $DOUMI_FILE, $DOUMI_NAME, $DOUMI_EXT")
                    .font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $draft.scriptValue)
                    .font(.system(size: 12, design: .monospaced)).frame(height: 56)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
            }
        }
    }
}

// MARK: - Action Row

private struct ActionRow: View {
    @Binding var draft: ActionDraft
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Picker("", selection: $draft.type) {
                        Section("File") {
                            Text("Move").tag(ActionDraftType.move)
                            Text("Copy").tag(ActionDraftType.copy)
                            Text("Rename").tag(ActionDraftType.rename)
                            Text("Sort into subfolder").tag(ActionDraftType.sortIntoSubfolder)
                            Text("Move to Trash").tag(ActionDraftType.trash)
                            Text("Delete").tag(ActionDraftType.delete)
                            Text("Archive (zip)").tag(ActionDraftType.archive)
                            Text("Unarchive").tag(ActionDraftType.unarchive)
                            Text("Make alias").tag(ActionDraftType.makeAlias)
                        }
                        Section("Metadata") {
                            Text("Add tags").tag(ActionDraftType.addTags)
                            Text("Remove tags").tag(ActionDraftType.removeTags)
                            Text("Set color label").tag(ActionDraftType.setColorLabel)
                            Text("Add comment").tag(ActionDraftType.addComment)
                            Text("Toggle extension").tag(ActionDraftType.toggleExtension)
                            Text("Toggle lock").tag(ActionDraftType.toggleLock)
                        }
                        Section("Open / Reveal") {
                            Text("Open").tag(ActionDraftType.openWith)
                            Text("Show in Finder").tag(ActionDraftType.showInFinder)
                        }
                        Section("Import") {
                            Text("Import into Music").tag(ActionDraftType.importMusic)
                            Text("Import into Photos").tag(ActionDraftType.importPhotos)
                            Text("Import into TV").tag(ActionDraftType.importTV)
                        }
                        Section("Notify / Log") {
                            Text("Display notification").tag(ActionDraftType.notify)
                            Text("Log").tag(ActionDraftType.log)
                        }
                        Section("Scripts") {
                            Text("Run shell script").tag(ActionDraftType.runShellScript)
                            Text("Run AppleScript").tag(ActionDraftType.runAppleScript)
                            Text("Run JavaScript").tag(ActionDraftType.runJavaScript)
                            Text("Run Automator workflow").tag(ActionDraftType.runAutomator)
                            Text("Run Shortcut").tag(ActionDraftType.runShortcut)
                        }
                        Section("Flow") {
                            Text("Continue matching rules").tag(ActionDraftType.continueMatching)
                            Text("Ignore").tag(ActionDraftType.ignore)
                        }
                    }
                    .frame(width: 195).fixedSize()
                    actionParams.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill").font(.system(size: 16)).foregroundStyle(.red.opacity(0.75))
            }
            .buttonStyle(.plain).padding(.top, 3)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
    }

    @ViewBuilder
    private var actionParams: some View {
        switch draft.type {
        case .move, .copy:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("to:").font(.system(size: 13)).foregroundStyle(.secondary)
                    TextField("~/Documents/Archive/", text: $draft.destination).textFieldStyle(.roundedBorder)
                    folderButton($draft.destination)
                }
                HStack(spacing: 10) { conflictPicker; createDirsToggle }
            }
        case .rename:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("to:").font(.system(size: 13)).foregroundStyle(.secondary)
                    TextField("{name}-{year}{month}{day}.{ext}", text: $draft.renameTo).textFieldStyle(.roundedBorder)
                }
                hint("{filename}  {name}  {ext}  {year}  {month}  {day}  {hour}  {minute}  {date}  {created_date}")
            }
        case .sortIntoSubfolder:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Base:").font(.system(size: 13)).foregroundStyle(.secondary)
                    TextField("~/Documents/", text: $draft.sortBase).textFieldStyle(.roundedBorder)
                    folderButton($draft.sortBase)
                }
                HStack(spacing: 8) {
                    Text("Organize by:").font(.caption).foregroundStyle(.secondary)
                    Picker("", selection: $draft.sortMode) {
                        ForEach(SortMode.allCases) { m in Text(m.rawValue).tag(m) }
                    }
                    .frame(width: 140).fixedSize()
                    if draft.sortMode == .custom {
                        TextField("{year}/{month}", text: $draft.sortCustomPattern)
                            .textFieldStyle(.roundedBorder).frame(width: 130)
                    } else {
                        Text(draft.sortMode.pattern(base: "")).font(.caption.monospaced()).foregroundStyle(.tertiary)
                    }
                }
                conflictPicker
            }
        case .trash:
            EmptyView()
        case .delete:
            Text("File will be permanently deleted — cannot be undone").font(.caption).foregroundStyle(.red.opacity(0.7))
        case .archive:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("In:").font(.system(size: 13)).foregroundStyle(.secondary)
                    TextField("Same folder as file", text: $draft.destination).textFieldStyle(.roundedBorder)
                    folderButton($draft.destination)
                }
                hint("Creates {name}.zip  •  Uses ditto --keepParent")
            }
        case .unarchive:
            HStack(spacing: 6) {
                Text("Into:").font(.system(size: 13)).foregroundStyle(.secondary)
                TextField("Same folder as archive", text: $draft.destination).textFieldStyle(.roundedBorder)
                folderButton($draft.destination)
            }
        case .makeAlias:
            HStack(spacing: 6) {
                Text("In:").font(.system(size: 13)).foregroundStyle(.secondary)
                TextField("~/Desktop", text: $draft.aliasDestination).textFieldStyle(.roundedBorder)
                folderButton($draft.aliasDestination)
            }
        case .addTags, .removeTags:
            HStack(spacing: 6) {
                Text("Tags:").font(.system(size: 13)).foregroundStyle(.secondary)
                TextField("work, important", text: $draft.tagsValue).textFieldStyle(.roundedBorder)
                    .help("Comma-separated tag names")
            }
        case .setColorLabel:
            HStack(spacing: 8) {
                Text("Label:").font(.system(size: 13)).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    ForEach(ColorLabel.allCases) { label in
                        Button { draft.colorLabel = label } label: {
                            Circle().fill(label.labelColor).frame(width: 20, height: 20)
                                .overlay(Circle().stroke(
                                    draft.colorLabel == label ? Color.accentColor : Color(NSColor.separatorColor),
                                    lineWidth: draft.colorLabel == label ? 2 : 0.5))
                        }
                        .buttonStyle(.plain).help(label.rawValue)
                    }
                }
                Text(draft.colorLabel.rawValue).font(.caption).foregroundStyle(.secondary)
            }
        case .addComment:
            HStack(spacing: 6) {
                Text("Comment:").font(.system(size: 13)).foregroundStyle(.secondary)
                TextField("Set Spotlight comment", text: $draft.commentText).textFieldStyle(.roundedBorder)
                    .help("Sets the Finder / Spotlight comment on the file")
            }
        case .toggleExtension:
            Text("Toggles the \"Hide Extension\" flag in Finder").font(.caption).foregroundStyle(.secondary)
        case .toggleLock:
            Text("Toggles the file's locked (immutable) flag").font(.caption).foregroundStyle(.secondary)
        case .openWith:
            HStack(spacing: 6) {
                Text("App:").font(.system(size: 13)).foregroundStyle(.secondary)
                TextField("Leave blank for default app", text: $draft.openWithApp).textFieldStyle(.roundedBorder)
            }
        case .showInFinder:
            Text("Reveals the file in a Finder window").font(.caption).foregroundStyle(.secondary)
        case .importMusic, .importPhotos, .importTV:
            Text("Imports the file into \(draft.type == .importMusic ? "Music" : draft.type == .importPhotos ? "Photos" : "TV") via AppleScript")
                .font(.caption).foregroundStyle(.secondary)
        case .notify:
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Title:").font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                    TextField("Doumi", text: $draft.notifTitle).textFieldStyle(.roundedBorder)
                }
                HStack(spacing: 6) {
                    Text("Message:").font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                    TextField("Processed {name}", text: $draft.notifMessage).textFieldStyle(.roundedBorder)
                }
                hint("{filename}  {name}  {ext}  {year}  {month}  {day}")
            }
        case .log:
            HStack(spacing: 6) {
                Text("Message:").font(.system(size: 13)).foregroundStyle(.secondary)
                TextField("{filename}", text: $draft.logMessage).textFieldStyle(.roundedBorder)
            }
        case .runShellScript, .runAppleScript, .runJavaScript:
            let lang = draft.type == .runAppleScript ? "AppleScript" : draft.type == .runJavaScript ? "JavaScript (JXA)" : "Shell"
            VStack(alignment: .leading, spacing: 4) {
                TextEditor(text: $draft.command)
                    .font(.system(size: 12, design: .monospaced)).frame(height: 56)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
                hint("\(lang)  •  $DOUMI_FILE  $DOUMI_NAME  $DOUMI_EXT")
            }
        case .runAutomator:
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Workflow:").font(.system(size: 13)).foregroundStyle(.secondary)
                    TextField("/path/to/workflow.workflow", text: $draft.command).textFieldStyle(.roundedBorder)
                    Button {
                        let panel = NSOpenPanel(); panel.allowedContentTypes = [.init(filenameExtension: "workflow")!]
                        panel.message = "Choose Automator workflow"; panel.prompt = "Select"
                        if panel.runModal() == .OK, let url = panel.url { draft.command = url.path }
                    } label: { Image(systemName: "folder") }.buttonStyle(.bordered).controlSize(.small)
                }
                hint("automator -i \"$DOUMI_FILE\" workflow.workflow")
            }
        case .runShortcut:
            HStack(spacing: 6) {
                Text("Shortcut:").font(.system(size: 13)).foregroundStyle(.secondary)
                TextField("My Shortcut", text: $draft.shortcutName).textFieldStyle(.roundedBorder)
                    .help("Name of a Shortcut from the Shortcuts app")
            }
        case .continueMatching:
            Text("Rule processing continues to the next rule (overrides \"stop after match\")").font(.caption).foregroundStyle(.secondary)
        case .ignore:
            Text("File is acknowledged with no action taken. Stops further rules if \"stop after match\" is on.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func hint(_ text: String) -> some View {
        Text(text).font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).lineLimit(1)
    }

    private var conflictPicker: some View {
        HStack(spacing: 4) {
            Text("If exists:").font(.caption).foregroundStyle(.secondary)
            Picker("", selection: $draft.onConflict) {
                Text("Rename automatically").tag(ConflictStrategy.rename)
                Text("Skip file").tag(ConflictStrategy.skip)
                Text("Overwrite").tag(ConflictStrategy.overwrite)
            }
            .frame(width: 172).fixedSize()
        }
    }

    private var createDirsToggle: some View {
        Toggle("Create folders", isOn: $draft.createDirs).toggleStyle(.checkbox).font(.caption)
    }

    private func folderButton(_ binding: Binding<String>) -> some View {
        Button {
            let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = "Select"
            if panel.runModal() == .OK, let url = panel.url {
                let home = FileManager.default.homeDirectoryForCurrentUser.path
                binding.wrappedValue = url.path.hasPrefix(home + "/")
                    ? "~" + String(url.path.dropFirst(home.count)) + "/"
                    : url.path + "/"
            }
        } label: { Image(systemName: "folder.badge.plus") }
        .buttonStyle(.bordered).controlSize(.small)
    }
}
