import SwiftUI
import AppKit
import DoumiCore

struct WatcherDetailView: View {
    let watcher: WatcherConfig
    let ruleSearch: String
    @Environment(AppState.self) private var state
    @State private var expandedRules: Set<UUID> = []
    @State private var showDisabled = true
    @State private var showRuleEditor = false
    @Environment(\.openWindow) private var openWindow

    private var expandedPath: String {
        (watcher.path as NSString).expandingTildeInPath
    }
    private var displayPath: String {
        watcher.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }

    private var filteredRules: [RuleConfig] {
        watcher.rules.filter { rule in
            let matchesSearch = ruleSearch.isEmpty ||
                (rule.name ?? "").localizedCaseInsensitiveContains(ruleSearch) ||
                rule.conditions.contains { c in conditionText(c).localizedCaseInsensitiveContains(ruleSearch) } ||
                rule.actions.contains { a in actionText(a).localizedCaseInsensitiveContains(ruleSearch) }
            let matchesFilter = showDisabled || rule.enabled
            return matchesSearch && matchesFilter
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            folderInfoBar
            if filteredRules.isEmpty {
                emptyState
            } else {
                ruleList
            }
        }
        // ── Context toolbar items (appear in window chrome) ─────
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Detach / reveal
                Menu {
                    Button {
                        NSWorkspace.shared.selectFile(nil,
                            inFileViewerRootedAtPath: expandedPath)
                    } label: { Label("Reveal in Finder", systemImage: "arrow.up.forward.app") }

                    Button {
                        openWindow(id: "watcher-detail",
                            value: watcher.id.uuidString)
                    } label: { Label("Detach to Window", systemImage: "arrow.up.left.and.arrow.down.right") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuIndicator(.hidden)
                .help("Folder options")
            }
        }
        .navigationTitle(watcher.name ?? displayPath)
        .navigationSubtitle(watcher.path.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~"))
        .sheet(isPresented: $showRuleEditor) {
            RuleEditorView(initialFolderPath: watcher.path) { folderPath, rule in
                state.addRule(rule, toFolderPath: folderPath)
            }
            .environment(state)
        }
    }

    // MARK: - Folder info bar
    private var folderInfoBar: some View {
        HStack(spacing: 10) {
            // Folder icon + status dot
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 28))
                    .foregroundStyle(.blue.gradient)
                Circle()
                    .fill(watcher.enabled ? Color.green : Color.gray)
                    .frame(width: 9, height: 9)
                    .overlay(Circle().stroke(Color(NSColor.windowBackgroundColor), lineWidth: 1.5))
            }

            // Path + metadata
            VStack(alignment: .leading, spacing: 3) {
                Text(displayPath)
                    .font(.headline)
                    .monospaced()
                    .lineLimit(1)

                HStack(spacing: 10) {
                    statusPill
                    if watcher.recursive {
                        metaBadge("Recursive", icon: "arrow.triangle.branch", color: .secondary)
                    }
                    metaBadge(
                        "\(watcher.rules.filter(\.enabled).count)/\(watcher.rules.count) rules",
                        icon: "checklist", color: .secondary)
                }
            }

            Spacer()

            // Inline action buttons (complement to toolbar)
            HStack(spacing: 6) {
                Button {
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: expandedPath)
                } label: {
                    Image(systemName: "folder.badge.magnifyingglass")
                        .imageScale(.medium)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Reveal in Finder")

                Button {
                    showRuleEditor = true
                } label: {
                    Label("New Rule", systemImage: "plus.square.on.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Create a new rule for this folder")

                Button {
                    state.runNow(watcher: watcher)
                } label: {
                    Label("Run Now", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(state.previewMode ? .indigo : .blue)
                .controlSize(.small)
                .help(state.previewMode
                    ? "Preview what rules would do on existing files"
                    : "Apply rules to all existing files right now")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    private var statusPill: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(watcher.enabled ? Color.green : Color.gray)
                .frame(width: 6, height: 6)
            Text(watcher.enabled ? "Active" : "Paused")
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(watcher.enabled ? .green : .secondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(
            (watcher.enabled ? Color.green : Color.gray).opacity(0.12),
            in: Capsule()
        )
    }

    private func metaBadge(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2)
            .foregroundStyle(color)
    }

    // MARK: - Rule list
    private var ruleList: some View {
        VStack(spacing: 0) {
            ruleListControls
            Divider()
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(filteredRules) { rule in
                        RuleCard(
                            rule: rule,
                            isExpanded: expandedRules.contains(rule.id),
                            onToggle: { toggleExpand(rule.id) },
                            onEnabledToggle: {
                                state.toggleRule(rule.id, inWatcher: watcher.id)
                            }
                        )
                        .contextMenu {
                            ruleContextMenu(rule: rule)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
    }

    private var ruleListControls: some View {
        HStack(spacing: 8) {
            Text("\(filteredRules.count) rule\(filteredRules.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Toggle(isOn: $showDisabled) {
                Label("Show Disabled", systemImage: "eye.slash")
                    .font(.caption)
            }
            .toggleStyle(.button)
            .controlSize(.mini)
            .buttonStyle(.bordered)
            .help("Show or hide disabled rules")

            Button {
                expandedRules.removeAll()
            } label: {
                Image(systemName: "chevron.up.2")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Collapse all rules")

            Button {
                expandedRules = Set(filteredRules.map(\.id))
            } label: {
                Image(systemName: "chevron.down.2")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Expand all rules")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(.bar)
    }

    @ViewBuilder
    private func ruleContextMenu(rule: RuleConfig) -> some View {
        Label(rule.name ?? "Rule", systemImage: "line.3.horizontal.decrease.circle")
            .font(.headline)
        Divider()
        Button {
            state.toggleRule(rule.id, inWatcher: watcher.id)
        } label: {
            Label(rule.enabled ? "Disable Rule" : "Enable Rule",
                  systemImage: rule.enabled ? "pause.circle" : "checkmark.circle")
        }
        Button {
            withAnimation { _ = expandedRules.insert(rule.id) }
        } label: {
            Label("Expand Details", systemImage: "chevron.down.circle")
        }
        Divider()
        Button(role: .destructive) {
            state.openConfigInEditor()
        } label: {
            Label("Delete Rule…", systemImage: "trash")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            if ruleSearch.isEmpty {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 44))
                    .foregroundStyle(.tertiary)
                Text("No rules yet")
                    .font(.title3)
                    .fontWeight(.medium)
                Text("Add rules to your config file to automate this folder.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Open Config in Editor") { state.openConfigInEditor() }
                    .buttonStyle(.borderedProminent).tint(.indigo)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 36))
                    .foregroundStyle(.tertiary)
                Text("No rules match \"\(ruleSearch)\"")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func toggleExpand(_ id: UUID) {
        if expandedRules.contains(id) { expandedRules.remove(id) }
        else { expandedRules.insert(id) }
    }

    // Text helpers for search
    private func conditionText(_ c: Condition) -> String {
        [c.glob, c.regex, c.equals, c.contains, c.run].compactMap { $0 }.joined(separator: " ")
    }
    private func actionText(_ a: Action) -> String {
        [a.to, a.command, a.message].compactMap { $0 }.joined(separator: " ")
    }
}

// MARK: - Rule Card

struct RuleCard: View {
    let rule: RuleConfig
    let isExpanded: Bool
    let onToggle: () -> Void
    let onEnabledToggle: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            cardHeader
            if isExpanded {
                Divider().padding(.horizontal, 10)
                cardBody
            }
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered
                    ? Color.accentColor.opacity(0.3)
                    : Color(NSColor.separatorColor).opacity(0.6),
                    lineWidth: 0.75)
        )
        .opacity(rule.enabled ? 1 : 0.55)
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private var cardBackground: Color {
        isHovered
            ? Color(NSColor.controlBackgroundColor).opacity(1)
            : Color(NSColor.controlBackgroundColor).opacity(0.7)
    }

    private var cardHeader: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                // Expand chevron
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
                    .frame(width: 10)

                // Rule type color strip
                RoundedRectangle(cornerRadius: 2)
                    .fill(ruleAccentColor.opacity(0.8))
                    .frame(width: 3, height: 22)

                // Name
                Text(rule.name ?? "Unnamed Rule")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(rule.enabled ? .primary : .secondary)
                    .lineLimit(1)

                Spacer()

                // Compact summary chips
                summaryChips

                // Enable/disable toggle button
                Button {
                    onEnabledToggle()
                } label: {
                    Image(systemName: rule.enabled ? "power.circle.fill" : "power.circle")
                        .font(.system(size: 15))
                        .foregroundStyle(rule.enabled ? Color.green : Color.gray.opacity(0.5))
                }
                .buttonStyle(.plain)
                .help(rule.enabled ? "Click to disable rule" : "Click to enable rule")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var ruleAccentColor: Color {
        guard let first = rule.actions.first else { return .gray }
        switch first.type {
        case .move, .rename:                                     return .blue
        case .fileCopy:                                          return .teal
        case .trash, .delete:                                    return .red
        case .run, .runJavaScript, .runAutomator:                return .orange
        case .notify:                                            return .purple
        case .log:                                               return .gray
        case .openWith:                                          return .green
        case .removeTags, .addComment, .toggleExtension,
             .toggleLock, .archive, .unarchive:                  return .indigo
        case .importMusic, .importPhotos, .importTV:             return .pink
        case .continueMatching:                                  return .cyan
        }
    }

    private var summaryChips: some View {
        HStack(spacing: 6) {
            chipLabel(
                icon: "questionmark.circle.fill",
                text: "\(rule.conditions.count)",
                color: .blue
            )
            Image(systemName: "arrow.right")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
            chipLabel(
                icon: primaryActionIcon,
                text: primaryActionLabel,
                color: ruleAccentColor
            )
        }
    }

    private var primaryActionIcon: String {
        switch rule.actions.first?.type {
        case .move:              return "arrow.right.circle.fill"
        case .fileCopy:          return "doc.on.doc.fill"
        case .rename:            return "pencil.circle.fill"
        case .trash:             return "trash.circle.fill"
        case .delete:            return "xmark.circle.fill"
        case .run, .runJavaScript, .runAutomator: return "terminal.fill"
        case .notify:            return "bell.fill"
        case .log:               return "doc.text.fill"
        case .openWith:          return "arrow.up.forward.app.fill"
        case .removeTags:        return "tag.slash.fill"
        case .addComment:        return "text.bubble.fill"
        case .toggleExtension:   return "eye.slash.fill"
        case .toggleLock:        return "lock.fill"
        case .archive:           return "archivebox.fill"
        case .unarchive:         return "archivebox"
        case .importMusic:       return "music.note"
        case .importPhotos:      return "photo.fill"
        case .importTV:          return "tv.fill"
        case .continueMatching:  return "arrow.down.circle.fill"
        case nil:                return "questionmark.circle.fill"
        }
    }

    private var primaryActionLabel: String {
        guard let a = rule.actions.first else { return "?" }
        switch a.type {
        case .move:              return a.to.map { shortPath($0) } ?? "move"
        case .fileCopy:          return a.to.map { shortPath($0) } ?? "copy"
        case .rename:            return a.to ?? "rename"
        case .trash:             return "Trash"
        case .delete:            return "Delete"
        case .run:               return "Script"
        case .runJavaScript:     return "JavaScript"
        case .runAutomator:      return "Automator"
        case .notify:            return "Notify"
        case .log:               return "Log"
        case .openWith:          return a.with ?? "Open"
        case .removeTags:        return "Remove Tags"
        case .addComment:        return "Comment"
        case .toggleExtension:   return "Ext Toggle"
        case .toggleLock:        return "Lock Toggle"
        case .archive:           return "Archive"
        case .unarchive:         return "Unarchive"
        case .importMusic:       return "→ Music"
        case .importPhotos:      return "→ Photos"
        case .importTV:          return "→ TV"
        case .continueMatching:  return "Continue"
        }
    }

    private func chipLabel(icon: String, text: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(text)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // MARK: - Expanded body
    private var cardBody: some View {
        HStack(alignment: .top, spacing: 20) {
            // Conditions column
            if !rule.conditions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    rowSectionHeader(
                        "IF \(rule.match == .all ? "ALL" : rule.match == .any ? "ANY" : "NONE")",
                        icon: "questionmark.circle.fill", color: .blue)
                    ForEach(Array(rule.conditions.enumerated()), id: \.offset) { _, c in
                        conditionRow(c)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !rule.conditions.isEmpty && !rule.actions.isEmpty {
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 20)
            }

            // Actions column
            if !rule.actions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    rowSectionHeader("THEN", icon: "bolt.fill", color: ruleAccentColor)
                    ForEach(Array(rule.actions.enumerated()), id: \.offset) { _, a in
                        actionRow(a)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(12)
    }

    private func rowSectionHeader(_ text: String, icon: String, color: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .textCase(.uppercase)
    }

    private func conditionRow(_ c: Condition) -> some View {
        HStack(spacing: 5) {
            Image(systemName: conditionIcon(c.type))
                .font(.system(size: 11))
                .foregroundStyle(.blue)
                .frame(width: 14)
            Text(conditionDescription(c))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private func actionRow(_ a: Action) -> some View {
        HStack(spacing: 5) {
            Image(systemName: primaryActionIcon)
                .font(.system(size: 11))
                .foregroundStyle(ruleAccentColor)
                .frame(width: 14)
            Text(actionDescription(a))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    // MARK: - Helpers

    private func shortPath(_ p: String) -> String {
        let s = p.replacingOccurrences(
            of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
        let parts = s.split(separator: "/")
        return parts.last.map(String.init) ?? s
    }

    private func conditionIcon(_ t: ConditionType) -> String {
        switch t {
        case .name, .fullName:        return "textformat.characters"
        case .ext:                    return "doc.badge.ellipsis"
        case .size:                   return "scalemass"
        case .age, .currentTime:      return "clock"
        case .kind:                   return "folder"
        case .script, .passesAppleScript, .passesJavaScript: return "terminal"
        case .tags:                   return "tag"
        case .colorLabel:             return "paintpalette"
        case .comment:                return "text.bubble"
        case .locked:                 return "lock"
        case .contents:               return "doc.text.magnifyingglass"
        case .sourceURL:              return "link"
        case .subfolderDepth:         return "arrow.down.right"
        case .subItemCount:           return "number.square"
        case .anyFile:                return "asterisk"
        }
    }

    private func conditionDescription(_ c: Condition) -> String {
        switch c.type {
        case .name:
            if let g = c.glob       { return "name matches \"\(g)\"" }
            if let r = c.regex      { return "name ~ /\(r)/" }
            if let e = c.equals     { return "name is \"\(e)\"" }
            if let s = c.startsWith { return "name starts with \"\(s)\"" }
            if let s = c.endsWith   { return "name ends with \"\(s)\"" }
            if let s = c.contains   { return "name contains \"\(s)\"" }
            return "name condition"
        case .ext:
            if let e = c.equals     { return "extension is .\(e)" }
            if let l = c.oneOf      { return "extension in [\(l.joined(separator: ", "))]" }
            if let n = c.not        { return "extension ≠ .\(n)" }
            return "extension condition"
        case .size:
            let sizeParts = [c.gt.map { "> \($0)" }, c.lt.map { "< \($0)" },
                             c.gte.map { "≥ \($0)" }, c.lte.map { "≤ \($0)" }].compactMap { $0 }
            return sizeParts.isEmpty ? "size condition" : sizeParts.joined(separator: "  ")
        case .age:
            let parts = [c.olderThan.map{"older than \($0)"},
                         c.newerThan.map{"newer than \($0)"}].compactMap{$0}
            return parts.isEmpty ? "age condition" : parts.joined(separator: ", ")
        case .kind:          return "is a \(c.equals ?? "file")"
        case .script, .passesAppleScript, .passesJavaScript: return "script: \(c.run ?? "")"
        case .tags:          return "has tags: \(c.oneOf?.joined(separator: ", ") ?? "")"
        case .fullName:      if let s = c.contains { return "full name contains \"\(s)\"" }; return "full name condition"
        case .colorLabel:    return "color label is \(c.colorLabelValue.map { String($0) } ?? "?")"
        case .comment:       if let s = c.contains { return "comment contains \"\(s)\"" }; return "comment condition"
        case .locked:        return c.locked == true ? "is locked" : "is not locked"
        case .contents:      if let s = c.contains { return "contents contain \"\(s)\"" }; return "contents condition"
        case .sourceURL:     if let s = c.contains { return "source URL contains \"\(s)\"" }; return "source URL condition"
        case .subfolderDepth: return "subfolder depth \(c.gt.map { "> \($0)" } ?? c.equals.map { "= \($0)" } ?? "condition")"
        case .subItemCount:  return "item count \(c.gt.map { "> \($0)" } ?? c.equals.map { "= \($0)" } ?? "condition")"
        case .anyFile:       return "any file"
        case .currentTime:   if let t = c.atTime { return "current time is \(t)" }; return "current time condition"
        }
    }

    private func actionDescription(_ a: Action) -> String {
        switch a.type {
        case .move:     return "Move → \(a.to ?? "(no destination)")"
        case .fileCopy: return "Copy → \(a.to ?? "(no destination)")"
        case .rename:   return "Rename → \"\(a.to ?? "(no template)")\""
        case .trash:    return "Move to Trash"
        case .delete:   return "Delete permanently"
        case .run:              return "Run: \(a.command ?? "")"
        case .runJavaScript:    return "Run JavaScript"
        case .runAutomator:     return "Run Automator: \(a.command ?? "")"
        case .notify:           return "Notify: \"\(a.message ?? "")\""
        case .log:              return "Log: \(a.message ?? "file path")"
        case .openWith:         return a.with.map { "Open with \($0)" } ?? "Open with default app"
        case .removeTags:       return "Remove tags: \(a.message ?? "")"
        case .addComment:       return "Add comment: \"\(a.message ?? "")\""
        case .toggleExtension:  return "Toggle extension visibility"
        case .toggleLock:       return "Toggle lock"
        case .archive:          return "Archive to zip"
        case .unarchive:        return "Unarchive"
        case .importMusic:      return "Import into Music"
        case .importPhotos:     return "Import into Photos"
        case .importTV:         return "Import into TV"
        case .continueMatching: return "Continue matching rules"
        }
    }
}
