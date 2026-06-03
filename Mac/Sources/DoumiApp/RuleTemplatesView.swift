import SwiftUI
import DoumiCore

// MARK: - Template model

enum TemplateCategory: String, CaseIterable, Identifiable {
    var id: String { rawValue }
    case inboxFinance  = "Inbox & Finance"
    case cleanup       = "Downloads & Cleanup"
    case developer     = "Developer"
    case media         = "Media & Photos"
    case archive       = "Projects & Archives"
    case advanced      = "Advanced Recipes"

    var icon: String {
        switch self {
        case .inboxFinance: "tray.fill"
        case .cleanup:      "trash.fill"
        case .developer:    "chevron.left.forwardslash.chevron.right"
        case .media:        "photo.stack.fill"
        case .archive:      "archivebox.fill"
        case .advanced:     "bolt.fill"
        }
    }
    var color: Color {
        switch self {
        case .inboxFinance: .green
        case .cleanup:      .red
        case .developer:    .orange
        case .media:        .purple
        case .archive:      .blue
        case .advanced:     .indigo
        }
    }
}

struct RuleTemplate: Identifiable {
    let id = UUID()
    let category: TemplateCategory
    let name: String
    let description: String
    let suggestedPath: String
    let rule: RuleConfig
}

// MARK: - Template Library

enum RuleTemplateLibrary {
    static let all: [RuleTemplate] = inboxFinance + cleanup + developer + media + archive + advanced

    // MARK: Inbox & Finance
    static let inboxFinance: [RuleTemplate] = [
        RuleTemplate(
            category: .inboxFinance,
            name: "Sort Financial Documents",
            description: "Moves invoices, receipts, payments and statements from Downloads into Finance/Receipts organized by year. Adds a 'Finance' Finder tag.",
            suggestedPath: "~/Downloads",
            rule: {
                var r = RuleConfig(); r.name = "Match and File Financial Documents"; r.match = .any
                var c1 = Condition(type: .name); c1.contains = "invoice"
                var c2 = Condition(type: .name); c2.contains = "receipt"
                var c3 = Condition(type: .name); c3.contains = "payment"
                var c4 = Condition(type: .name); c4.contains = "statement"
                var c5 = Condition(type: .name); c5.regex = "bill[-_]\\d+"
                r.conditions = [c1,c2,c3,c4,c5]
                var a1 = Action(type: .move); a1.to = "~/Documents/Finance/Receipts/{year}/"; a1.onConflict = .rename
                var a2 = Action(type: .notify); a2.title = "Finance Organizer"; a2.message = "Sorted: {filename}"
                var a3 = Action(type: .run); a3.command = "tag --add 'Finance' \"$DOUMI_FILE\""
                r.actions = [a1,a2,a3]; return r
            }()
        ),
        RuleTemplate(
            category: .inboxFinance,
            name: "Auto-file IRS Tax Forms",
            description: "Uses Spotlight to scan PDF text content for tax keywords (1099-MISC, W-2, Form 1040) and files them into Finance/Taxes/{year}/.",
            suggestedPath: "~/Downloads",
            rule: {
                var r = RuleConfig(); r.name = "Auto-file IRS Tax Forms"; r.match = .all
                var c1 = Condition(type: .ext); c1.equals = "pdf"
                var c2 = Condition(type: .script); c2.run = "mdls -name kMDItemTextContent \"$DOUMI_FILE\" | grep -Eiq \"1099-MISC|W-2|Form 1040\""
                r.conditions = [c1,c2]
                var a1 = Action(type: .move); a1.to = "~/Documents/Finance/Taxes/{year}/"; a1.onConflict = .rename
                var a2 = Action(type: .run); a2.command = "tag --add 'Taxes' \"$DOUMI_FILE\""
                r.actions = [a1,a2]; return r
            }()
        ),
    ]

    // MARK: Downloads & Cleanup
    static let cleanup: [RuleTemplate] = [
        RuleTemplate(
            category: .cleanup,
            name: "Trash Stale Installer Files",
            description: "Moves DMG, PKG, ISO, ZIP and archive files from Downloads to Trash after 7 days of inactivity. Notifies when cleaned.",
            suggestedPath: "~/Downloads",
            rule: {
                var r = RuleConfig(); r.name = "Trash installer files older than 7 days"; r.match = .all
                var c1 = Condition(type: .ext); c1.oneOf = ["dmg","pkg","iso","zip","tar","gz"]
                var c2 = Condition(type: .age); c2.olderThan = "7d"
                r.conditions = [c1,c2]
                var a1 = Action(type: .trash)
                var a2 = Action(type: .notify); a2.title = "Downloads Cleaned"; a2.message = "Trashed stale installer: {filename}"
                r.actions = [a1,a2]; return r
            }()
        ),
        RuleTemplate(
            category: .cleanup,
            name: "Archive Stale Documents",
            description: "Moves PDFs, Word docs, spreadsheets and presentations that have sat in Downloads for 14+ days into Documents/Archive/Downloads/{year}/.",
            suggestedPath: "~/Downloads",
            rule: {
                var r = RuleConfig(); r.name = "Move stale PDFs and Docs to Archive after 14 days"; r.match = .all
                var c1 = Condition(type: .ext); c1.oneOf = ["pdf","docx","doc","xlsx","csv","pptx"]
                var c2 = Condition(type: .age); c2.olderThan = "14d"
                r.conditions = [c1,c2]
                var a1 = Action(type: .move); a1.to = "~/Documents/Archive/Downloads/{year}/"; a1.onConflict = .rename
                var a2 = Action(type: .log); a2.message = "Archived stale download: {filename}"
                r.actions = [a1,a2]; return r
            }()
        ),
        RuleTemplate(
            category: .cleanup,
            name: "Delete Zero-Byte Files",
            description: "Permanently deletes empty (0-byte) files that are at least 1 day old — catches failed downloads and corrupt stubs.",
            suggestedPath: "~/Downloads",
            rule: {
                var r = RuleConfig(); r.name = "Delete zero-byte / empty files"; r.match = .all
                var c1 = Condition(type: .kind); c1.equals = "file"
                var c2 = Condition(type: .size); c2.lte = "0b"
                var c3 = Condition(type: .age); c3.olderThan = "1d"
                r.conditions = [c1,c2,c3]
                r.actions = [Action(type: .delete)]; return r
            }()
        ),
        RuleTemplate(
            category: .cleanup,
            name: "Delete Empty Folders",
            description: "Recursively scans Downloads for completely empty directories and deletes them, keeping the folder tidy.",
            suggestedPath: "~/Downloads",
            rule: {
                var r = RuleConfig(); r.name = "Delete Empty Folders"; r.match = .all
                var c1 = Condition(type: .kind); c1.equals = "directory"
                var c2 = Condition(type: .script); c2.run = "[ -d \"$DOUMI_FILE\" ] && [ -z \"$(ls -A \"$DOUMI_FILE\")\" ]"
                r.conditions = [c1,c2]
                var a1 = Action(type: .delete)
                var a2 = Action(type: .log); a2.message = "Deleted empty directory: {filename}"
                r.actions = [a1,a2]; return r
            }()
        ),
    ]

    // MARK: Developer
    static let developer: [RuleTemplate] = [
        RuleTemplate(
            category: .developer,
            name: "Tag Dirty Git Repos",
            description: "Scans your Developer folder for Git repos with uncommitted changes and adds a 'Dirty' Finder tag so they stand out at a glance.",
            suggestedPath: "~/Developer",
            rule: {
                var r = RuleConfig(); r.name = "Auto-tag active Git repos with uncommitted changes"; r.match = .all
                var c1 = Condition(type: .kind); c1.equals = "directory"
                var c2 = Condition(type: .script); c2.run = "[ -d \"$DOUMI_FILE/.git\" ]"
                var c3 = Condition(type: .script); c3.run = "cd \"$DOUMI_FILE\" && ! git diff --quiet"
                r.conditions = [c1,c2,c3]
                var a1 = Action(type: .run); a1.command = "tag --add 'Dirty' \"$DOUMI_FILE\""
                var a2 = Action(type: .log); a2.message = "Repo '{filename}' has active changes — tagged Dirty"
                r.actions = [a1,a2]; return r
            }()
        ),
        RuleTemplate(
            category: .developer,
            name: "Tag Clean Git Repos",
            description: "Removes the 'Dirty' tag and adds a 'Clean' tag to Git repositories where both working tree and index are unmodified.",
            suggestedPath: "~/Developer",
            rule: {
                var r = RuleConfig(); r.name = "Remove Dirty tag from clean Git repos"; r.match = .all
                var c1 = Condition(type: .kind); c1.equals = "directory"
                var c2 = Condition(type: .script); c2.run = "[ -d \"$DOUMI_FILE/.git\" ]"
                var c3 = Condition(type: .script); c3.run = "cd \"$DOUMI_FILE\" && git diff --quiet && git diff --cached --quiet"
                r.conditions = [c1,c2,c3]
                var a1 = Action(type: .run); a1.command = "tag --remove 'Dirty' \"$DOUMI_FILE\""
                var a2 = Action(type: .run); a2.command = "tag --add 'Clean' \"$DOUMI_FILE\""
                r.actions = [a1,a2]; return r
            }()
        ),
        RuleTemplate(
            category: .developer,
            name: "Collect Patch & Diff Files",
            description: "Automatically moves .patch and .diff files into ~/Developer/Patches/ so stray patch files don't litter your project folders.",
            suggestedPath: "~/Developer",
            rule: {
                var r = RuleConfig(); r.name = "Organize patch and diff files"; r.match = .all
                var c1 = Condition(type: .ext); c1.oneOf = ["patch","diff"]
                r.conditions = [c1]
                var a1 = Action(type: .move); a1.to = "~/Developer/Patches/"; a1.onConflict = .rename
                var a2 = Action(type: .notify); a2.title = "Developer Organizer"; a2.message = "Moved patch: {filename}"
                r.actions = [a1,a2]; return r
            }()
        ),
        RuleTemplate(
            category: .developer,
            name: "Archive Crash Logs & Debug Reports",
            description: "Moves log files, crash reports and stack traces into Developer/Logs/{year}-{month}/ to keep project folders clean.",
            suggestedPath: "~/Developer",
            rule: {
                var r = RuleConfig(); r.name = "Organize crash logs and debug reports"; r.match = .any
                var c1 = Condition(type: .ext); c1.oneOf = ["log","crash","stacktrace"]
                var c2 = Condition(type: .name); c2.glob = "*_log*"
                r.conditions = [c1,c2]
                var a1 = Action(type: .move); a1.to = "~/Developer/Logs/{year}-{month}/"; a1.onConflict = .rename
                r.actions = [a1]; return r
            }()
        ),
    ]

    // MARK: Media & Photos
    static let media: [RuleTemplate] = [
        RuleTemplate(
            category: .media,
            name: "Sort Screenshots by Date",
            description: "Uses macOS Spotlight metadata (kMDItemIsScreenCapture) to identify screenshots regardless of filename, then sorts them into Pictures/Screenshots/{year}/{month}/.",
            suggestedPath: "~/Downloads",
            rule: {
                var r = RuleConfig(); r.name = "Identify Screenshots via macOS Metadata"; r.match = .all
                var c1 = Condition(type: .ext); c1.oneOf = ["png","jpg","jpeg","tiff"]
                var c2 = Condition(type: .script); c2.run = "mdls -name kMDItemIsScreenCapture \"$DOUMI_FILE\" | grep -q \"1\""
                r.conditions = [c1,c2]
                var a1 = Action(type: .move); a1.to = "~/Pictures/Screenshots/{year}/{month}/"; a1.onConflict = .rename
                var a2 = Action(type: .notify); a2.title = "Media Sorter"; a2.message = "Sorted screenshot: {filename}"
                r.actions = [a1,a2]; return r
            }()
        ),
        RuleTemplate(
            category: .media,
            name: "Sort iPhone Photos (EXIF)",
            description: "Reads EXIF acquisition model metadata to detect iPhone photos and moves them into Pictures/iPhone-Photos/{year}/{month}/.",
            suggestedPath: "~/Downloads",
            rule: {
                var r = RuleConfig(); r.name = "Sort Photos by Camera Device (EXIF)"; r.match = .all
                var c1 = Condition(type: .ext); c1.oneOf = ["jpg","jpeg","heic"]
                var c2 = Condition(type: .script); c2.run = "mdls -name kMDItemAcquisitionModel \"$DOUMI_FILE\" | grep -iq \"iPhone\""
                r.conditions = [c1,c2]
                var a1 = Action(type: .move); a1.to = "~/Pictures/iPhone-Photos/{year}/{month}/"; a1.onConflict = .rename
                r.actions = [a1]; return r
            }()
        ),
        RuleTemplate(
            category: .media,
            name: "Route Slack Downloads",
            description: "Checks the download origin URL metadata (kMDItemWhereFroms) for Slack links and moves those files into a dedicated Slack-Files folder.",
            suggestedPath: "~/Downloads",
            rule: {
                var r = RuleConfig(); r.name = "Route Slack Downloads"; r.match = .all
                var c1 = Condition(type: .script); c1.run = "mdls -name kMDItemWhereFroms \"$DOUMI_FILE\" | grep -iq \"slack\""
                r.conditions = [c1]
                var a1 = Action(type: .move); a1.to = "~/Downloads/Slack-Files/"; a1.onConflict = .rename
                var a2 = Action(type: .run); a2.command = "tag --add 'Slack' \"$DOUMI_FILE\""
                r.actions = [a1,a2]; return r
            }()
        ),
        RuleTemplate(
            category: .media,
            name: "Route GitHub Downloads",
            description: "Detects files downloaded from GitHub via origin URL metadata and collects them into Downloads/GitHub-Downloads/.",
            suggestedPath: "~/Downloads",
            rule: {
                var r = RuleConfig(); r.name = "Route GitHub Downloads"; r.match = .all
                var c1 = Condition(type: .script); c1.run = "mdls -name kMDItemWhereFroms \"$DOUMI_FILE\" | grep -iq \"github\""
                r.conditions = [c1]
                var a1 = Action(type: .move); a1.to = "~/Downloads/GitHub-Downloads/"; a1.onConflict = .rename
                var a2 = Action(type: .run); a2.command = "tag --add 'GitHub' \"$DOUMI_FILE\""
                r.actions = [a1,a2]; return r
            }()
        ),
        RuleTemplate(
            category: .media,
            name: "Separate High-Res Stock Photos",
            description: "Uses sips to read pixel dimensions — routes images wider than 2000px to Stock-Photos/ and tags them 'High-Res'.",
            suggestedPath: "~/Downloads",
            rule: {
                var r = RuleConfig(); r.name = "Route High-Res Stock Images"; r.match = .all
                var c1 = Condition(type: .ext); c1.oneOf = ["jpg","jpeg","png","heic"]
                var c2 = Condition(type: .script); c2.run = "width=$(sips -g pixelWidth \"$DOUMI_FILE\" | awk '/pixelWidth/ {print $2}'); [ \"$width\" -gt 2000 ]"
                r.conditions = [c1,c2]
                var a1 = Action(type: .move); a1.to = "~/Pictures/Stock-Photos/"; a1.onConflict = .rename
                var a2 = Action(type: .run); a2.command = "tag --add 'High-Res' \"$DOUMI_FILE\""
                r.actions = [a1,a2]; return r
            }()
        ),
        RuleTemplate(
            category: .media,
            name: "Route Code Screenshots to Work",
            description: "Detects screenshots taken while Xcode, VS Code, or Terminal was active (using kMDItemTitle metadata) and files them under Work/Code-Screenshots/.",
            suggestedPath: "~/Desktop",
            rule: {
                var r = RuleConfig(); r.name = "Route Code Screenshots to Work"; r.match = .all
                var c1 = Condition(type: .name); c1.startsWith = "Screenshot"
                var c2 = Condition(type: .script); c2.run = "mdls -name kMDItemTitle \"$DOUMI_FILE\" | grep -Eiq \"Xcode|VS Code|Terminal\""
                r.conditions = [c1,c2]
                var a1 = Action(type: .move); a1.to = "~/Documents/Work/Code-Screenshots/"; a1.onConflict = .rename
                r.actions = [a1]; return r
            }()
        ),
    ]

    // MARK: Projects & Archives
    static let archive: [RuleTemplate] = [
        RuleTemplate(
            category: .archive,
            name: "Compress Stale Projects",
            description: "Watches Developer/Projects for directories untouched for 90 days, compresses them to .tar.gz in Developer/Archive/, then removes the original folder. Notifies on completion.",
            suggestedPath: "~/Developer/Projects",
            rule: {
                var r = RuleConfig(); r.name = "Compress and Archive Stale Projects"; r.match = .all
                var c1 = Condition(type: .kind); c1.equals = "directory"
                var c2 = Condition(type: .age); c2.olderThan = "90d"
                var c3 = Condition(type: .script); c3.run = "[[ ! \"$DOUMI_NAME\" =~ ^\\. ]]"
                r.conditions = [c1,c2,c3]
                var a1 = Action(type: .log); a1.message = "Archiving stale project: {filename}"
                var a2 = Action(type: .run); a2.command = "mkdir -p ~/Developer/Archive && tar -czf ~/Developer/Archive/{name}-{date}.tar.gz -C \"$(dirname \"$DOUMI_FILE\")\" \"{filename}\" && rm -rf \"$DOUMI_FILE\""
                var a3 = Action(type: .notify); a3.title = "Project Archiver"; a3.message = "Archived {filename} → Developer/Archive/"
                r.actions = [a1,a2,a3]; return r
            }()
        ),
    ]

    // MARK: Advanced Recipes
    static let advanced: [RuleTemplate] = [
        RuleTemplate(
            category: .advanced,
            name: "Transcode MOV to WebM (ffmpeg)",
            description: "Watches a Renders folder. After a MOV sits untouched for 2 minutes (confirming the render is done), transcodes it to WebM with VP9/Opus using ffmpeg, then trashes the original. Requires: brew install ffmpeg.",
            suggestedPath: "~/Movies/Renders",
            rule: {
                var r = RuleConfig(); r.name = "Transcode Rendered MOV to WebM"; r.match = .all
                var c1 = Condition(type: .ext); c1.equals = "mov"
                var c2 = Condition(type: .age); c2.olderThan = "2m"
                r.conditions = [c1,c2]
                var a1 = Action(type: .run); a1.command = "ffmpeg -i \"$DOUMI_FILE\" -c:v vp9 -b:v 1M -c:a libopus ~/Movies/Web-Ready/\"$DOUMI_NAME\".webm"
                var a2 = Action(type: .trash)
                r.actions = [a1,a2]; return r
            }()
        ),
        RuleTemplate(
            category: .advanced,
            name: "Desktop Auto-Cleaner",
            description: "Catches any file that lands on the Desktop and has been sitting there unmodified for more than 3 days, moving it into Documents/Desktop-Archive/{year}-{month}/.",
            suggestedPath: "~/Desktop",
            rule: {
                var r = RuleConfig(); r.name = "Archive stale Desktop files"; r.match = .all
                var c1 = Condition(type: .kind); c1.equals = "file"
                var c2 = Condition(type: .age); c2.olderThan = "3d"
                r.conditions = [c1,c2]
                var a1 = Action(type: .move); a1.to = "~/Documents/Desktop-Archive/{year}-{month}/"; a1.onConflict = .rename
                r.actions = [a1]; return r
            }()
        ),
        RuleTemplate(
            category: .advanced,
            name: "Auto-Rename Generic Downloads",
            description: "Detects files with generic names (e.g. document(1).pdf, Untitled) and renames them to include the modification date, helping you find them later.",
            suggestedPath: "~/Downloads",
            rule: {
                var r = RuleConfig(); r.name = "Date-stamp generic filenames"; r.match = .any
                var c1 = Condition(type: .name); c1.glob = "document(*"
                var c2 = Condition(type: .name); c2.glob = "Untitled*"
                var c3 = Condition(type: .name); c3.glob = "download*"
                r.conditions = [c1,c2,c3]
                var a1 = Action(type: .rename); a1.to = "{name}-{date}.{ext}"
                r.actions = [a1]; return r
            }()
        ),
        RuleTemplate(
            category: .advanced,
            name: "Nightly Log Rotation",
            description: "Moves any .log file older than 24 hours out of a watched log directory and into a dated archive folder, keeping the working directory clean.",
            suggestedPath: "~/Library/Logs",
            rule: {
                var r = RuleConfig(); r.name = "Rotate logs older than 24 hours"; r.match = .all
                var c1 = Condition(type: .ext); c1.equals = "log"
                var c2 = Condition(type: .age); c2.olderThan = "24h"
                r.conditions = [c1,c2]
                var a1 = Action(type: .move); a1.to = "~/Library/Logs/Archive/{year}-{month}/"; a1.onConflict = .rename
                r.actions = [a1]; return r
            }()
        ),
    ]
}

// MARK: - Templates View

struct RuleTemplatesView: View {
    @Environment(AppState.self) private var state
    @State private var selectedCategory: TemplateCategory? = nil
    @State private var searchText = ""
    @State private var addingTemplate: RuleTemplate? = nil
    @State private var expandedTemplates: Set<UUID> = []

    private var filtered: [RuleTemplate] {
        let source = selectedCategory.map { cat in
            RuleTemplateLibrary.all.filter { $0.category == cat }
        } ?? RuleTemplateLibrary.all
        guard !searchText.isEmpty else { return source }
        let q = searchText.lowercased()
        return source.filter {
            $0.name.lowercased().contains(q) ||
            $0.description.lowercased().contains(q) ||
            $0.category.rawValue.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Category filter strip
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    categoryChip(nil, label: "All", icon: "square.grid.2x2.fill", color: .secondary)
                    ForEach(TemplateCategory.allCases) { cat in
                        categoryChip(cat, label: cat.rawValue, icon: cat.icon, color: cat.color)
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 10)
            }
            .background(.bar)
            .overlay(alignment: .bottom) { Divider() }

            if filtered.isEmpty {
                emptySearch
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filtered) { template in
                            TemplateCard(
                                template: template,
                                isExpanded: expandedTemplates.contains(template.id),
                                onToggle: { toggleExpand(template.id) },
                                onAdd: { addingTemplate = template }
                            )
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Rule Library")
        .navigationSubtitle("\(RuleTemplateLibrary.all.count) templates")
        .searchable(text: $searchText, prompt: "Search templates…")
        .sheet(item: $addingTemplate) { template in
            AddTemplateSheet(template: template)
                .environment(state)
        }
    }

    private func categoryChip(_ cat: TemplateCategory?, label: String, icon: String, color: Color) -> some View {
        let selected = selectedCategory == cat
        return Button { selectedCategory = cat } label: {
            Label(label, systemImage: icon)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? .white : color)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(selected ? color : color.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func toggleExpand(_ id: UUID) {
        if expandedTemplates.contains(id) { expandedTemplates.remove(id) }
        else { expandedTemplates.insert(id) }
    }

    private var emptySearch: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("No templates match \"\(searchText)\"").foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }
}

// MARK: - Template Card

private struct TemplateCard: View {
    let template: RuleTemplate
    let isExpanded: Bool
    let onToggle: () -> Void
    let onAdd: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 0) {
            // Header row
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    // Category icon badge
                    ZStack {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(template.category.color.opacity(0.15))
                            .frame(width: 36, height: 36)
                        Image(systemName: template.category.icon)
                            .font(.system(size: 15))
                            .foregroundStyle(template.category.color)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(template.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)
                        Text(template.category.rawValue)
                            .font(.caption2)
                            .foregroundStyle(template.category.color)
                            .fontWeight(.medium)
                    }

                    Spacer()

                    // Stats chips
                    HStack(spacing: 6) {
                        statChip("\(template.rule.conditions.count) cond", color: .blue)
                        statChip("\(template.rule.actions.count) action\(template.rule.actions.count == 1 ? "" : "s")", color: template.category.color)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2).fontWeight(.semibold).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                Divider().padding(.horizontal, 10)

                VStack(alignment: .leading, spacing: 12) {
                    // Description
                    Text(template.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // Conditions + Actions preview
                    HStack(alignment: .top, spacing: 16) {
                        // Conditions
                        if !template.rule.conditions.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("IF \(template.rule.match == .all ? "ALL" : template.rule.match == .any ? "ANY" : "NONE")",
                                      systemImage: "questionmark.circle.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.blue)
                                ForEach(Array(template.rule.conditions.enumerated()), id: \.offset) { _, c in
                                    HStack(spacing: 4) {
                                        Image(systemName: condIcon(c.type)).font(.system(size: 10)).foregroundStyle(.blue).frame(width: 12)
                                        Text(condSummary(c)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.tertiary).padding(.top, 14)

                        // Actions
                        if !template.rule.actions.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Label("THEN", systemImage: "bolt.fill")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(template.category.color)
                                ForEach(Array(template.rule.actions.enumerated()), id: \.offset) { _, a in
                                    HStack(spacing: 4) {
                                        Image(systemName: actionIcon(a.type)).font(.system(size: 10)).foregroundStyle(template.category.color).frame(width: 12)
                                        Text(actionSummary(a)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    // Footer
                    HStack {
                        Label("Suggested: \(template.suggestedPath)", systemImage: "folder")
                            .font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Button { onAdd() } label: {
                            Label("Add to Config", systemImage: "plus.circle.fill")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(template.category.color)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 14).padding(.bottom, 12).padding(.top, 8)
            }
        }
        .background(
            isHovered ? Color(NSColor.controlBackgroundColor) : Color(NSColor.controlBackgroundColor).opacity(0.7)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isHovered ? template.category.color.opacity(0.35) : Color(NSColor.separatorColor).opacity(0.5),
                        lineWidth: 0.75)
        )
        .onHover { isHovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: isHovered)
    }

    private func statChip(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.1), in: Capsule())
    }

    private func condIcon(_ t: ConditionType) -> String {
        switch t {
        case .name, .fullName:       "textformat.characters"
        case .ext:                   "doc.badge.ellipsis"
        case .size:                  "scalemass"
        case .age, .currentTime:     "clock"
        case .kind:                  "folder"
        case .script, .passesAppleScript, .passesJavaScript: "terminal"
        case .tags:                  "tag"
        case .colorLabel:            "paintpalette"
        case .comment:               "text.bubble"
        case .locked:                "lock"
        case .contents:              "doc.text.magnifyingglass"
        case .sourceURL:             "link"
        case .subfolderDepth:        "arrow.down.right"
        case .subItemCount:          "number.square"
        case .anyFile:               "asterisk"
        }
    }

    private func condSummary(_ c: Condition) -> String {
        switch c.type {
        case .name, .fullName:
            if let s = c.contains   { return "name contains \"\(s)\"" }
            if let g = c.glob       { return "name matches \"\(g)\"" }
            if let r = c.regex      { return "name ~ /\(r)/" }
            if let s = c.startsWith { return "name starts with \"\(s)\"" }
            if let s = c.endsWith   { return "name ends with \"\(s)\"" }
            return "name condition"
        case .ext:
            if let l = c.oneOf      { return "ext in [\(l.joined(separator: ", "))]" }
            if let e = c.equals     { return "ext is .\(e)" }
            return "extension condition"
        case .age:
            if let s = c.olderThan  { return "older than \(s)" }
            if let s = c.newerThan  { return "newer than \(s)" }
            return "age condition"
        case .kind:   return "is a \(c.equals ?? "file")"
        case .script: return "script condition"
        case .size:
            if let s = c.lte        { return "size ≤ \(s)" }
            if let s = c.gt         { return "size > \(s)" }
            return "size condition"
        case .tags:   return "has tags"
        default:      return "\(c.type.rawValue) condition"
        }
    }

    private func actionIcon(_ t: ActionType) -> String {
        switch t {
        case .move:    "arrow.right.circle.fill"
        case .fileCopy: "doc.on.doc.fill"
        case .rename:  "pencil.circle.fill"
        case .trash:   "trash.circle.fill"
        case .delete:  "xmark.circle.fill"
        case .run, .runJavaScript, .runAutomator: "terminal.fill"
        case .notify:  "bell.fill"
        case .log:     "doc.text.fill"
        case .openWith: "arrow.up.forward.app.fill"
        default:       "bolt.fill"
        }
    }

    private func actionSummary(_ a: Action) -> String {
        switch a.type {
        case .move:    return "Move → \(a.to.map { shortPath($0) } ?? "?")"
        case .fileCopy: return "Copy → \(a.to.map { shortPath($0) } ?? "?")"
        case .rename:  return "Rename → \(a.to ?? "?")"
        case .trash:   return "Move to Trash"
        case .delete:  return "Delete permanently"
        case .run:     return "Run: \((a.command ?? "").prefix(40))"
        case .notify:  return "Notify: \(a.message ?? "")"
        case .log:     return "Log: \(a.message ?? "file path")"
        case .openWith: return a.with.map { "Open with \($0)" } ?? "Open"
        default:       return a.type.rawValue
        }
    }

    private func shortPath(_ p: String) -> String {
        p.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

// MARK: - Add Template Sheet

private struct AddTemplateSheet: View {
    let template: RuleTemplate
    @Environment(AppState.self) private var state
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPath: String = ""
    private var suggestedFolders: [(name: String, path: String)] {
        var base: [(String, String)] = []
        // Watched folders first
        for w in state.config.watch { base.append((shortPath(w.path), w.path)) }
        // Common
        for f in [("Desktop","~/Desktop"),("Downloads","~/Downloads"),("Documents","~/Documents"),
                  ("Developer","~/Developer"),("Pictures","~/Pictures"),("Movies","~/Movies")] {
            if !base.contains(where: { $0.1 == f.1 }) &&
               FileManager.default.fileExists(atPath: (f.1 as NSString).expandingTildeInPath) {
                base.append(f)
            }
        }
        return base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(template.category.color.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: template.category.icon).font(.system(size: 20)).foregroundStyle(template.category.color)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name).font(.headline)
                    Text(template.category.rawValue).font(.caption).foregroundStyle(template.category.color)
                }
            }

            Text(template.description).font(.system(size: 12)).foregroundStyle(.secondary)

            Divider()

            // Folder picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Add this rule to:").font(.system(size: 13, weight: .medium))
                HStack(spacing: 8) {
                    Picker("", selection: $selectedPath) {
                        if !state.config.watch.isEmpty {
                            Section("Watched Folders") {
                                ForEach(state.config.watch) { w in Text(shortPath(w.path)).tag(w.path) }
                            }
                        }
                        Section("Common Folders") {
                            ForEach(suggestedFolders, id: \.1) { name, path in Text(name).tag(path) }
                        }
                    }
                    .frame(width: 220)
                    Button("Browse…") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.prompt = "Select"
                        if panel.runModal() == .OK, let url = panel.url {
                            let home = FileManager.default.homeDirectoryForCurrentUser.path
                            selectedPath = url.path.hasPrefix(home + "/")
                                ? "~" + String(url.path.dropFirst(home.count)) : url.path
                        }
                    }
                    .buttonStyle(.bordered)
                }
                Text("The rule will be added to the watcher for this folder. A new watcher will be created if needed.")
                    .font(.caption).foregroundStyle(.tertiary)
            }

            Spacer()

            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Add Rule") {
                    state.addRule(template.rule, toFolderPath: selectedPath)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(template.category.color)
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPath.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 460, height: 360)
        .onAppear {
            // Pre-select the suggested path if it's watched, otherwise use it as-is
            let suggested = template.suggestedPath
            selectedPath = state.config.watch.first(where: { $0.path == suggested })?.path ?? suggested
        }
    }

    private func shortPath(_ p: String) -> String {
        p.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}
