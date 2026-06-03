import SwiftUI
import AppKit
import DoumiCore

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var selection: SidebarItem? = .watchers
    @State private var ruleSearch = ""
    @Environment(\.openWindow) private var openWindow

    enum SidebarItem: Hashable { case watchers, activity, settings }

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 290)
        } detail: {
            detailView
        }
        .frame(minWidth: 800, minHeight: 540)
        // ── Global toolbar ──────────────────────────────────────────
        .toolbar {
            // ── Group A: CREATE ──────────────────────────────────
            ToolbarItem(id: "add-folder", placement: .navigation) {
                Button {
                    state.promptAddFolder()
                } label: {
                    Label("Add Folder", systemImage: "plus.rectangle.on.folder")
                }
                .help("Add a new folder to watch")
            }

            ToolbarItem(id: "new-rule", placement: .navigation) {
                Menu {
                    Button {
                        state.openConfigInEditor()
                    } label: {
                        Label("New Rule in Current Folder", systemImage: "text.badge.plus")
                    }
                    Button {
                        state.openConfigInEditor()
                    } label: {
                        Label("New Rule Group", systemImage: "folder.badge.plus")
                    }
                } label: {
                    Label("New Rule", systemImage: "plus.square.on.square")
                }
                .help("Add a rule or rule group")
            }

            // ── Group B: CONTROL ─────────────────────────────────
            ToolbarItem(id: "run-now", placement: .primaryAction) {
                Menu {
                    Button("Run on Current Folder") {
                        state.runNow(watcher: state.selectedWatcher)
                    }
                    .disabled(state.selectedWatcher == nil)
                    Button("Run on All Folders") {
                        state.runNow()
                    }
                } label: {
                    Label("Run", systemImage: "play.fill")
                }
                .menuIndicator(.visible)
                .help("Apply rules to existing files right now")
            }

            ToolbarItem(id: "pause", placement: .primaryAction) {
                Button {
                    if state.isRunning { state.stopWatching() } else { state.restart() }
                } label: {
                    Label(
                        state.isRunning ? "Pause Watching" : "Resume Watching",
                        systemImage: state.isRunning ? "pause.fill" : "play.fill"
                    )
                }
                .foregroundStyle(state.isRunning ? .orange : .green)
                .symbolEffect(.pulse, isActive: state.isRunning)
                .help(state.isRunning ? "Pause all rule watching" : "Resume watching")
            }

            // ── Group C: INSPECT ─────────────────────────────────
            ToolbarItem(id: "preview", placement: .primaryAction) {
                Toggle(isOn: Binding(
                    get: { state.previewMode },
                    set: { _ in state.togglePreviewMode() }
                )) {
                    Label("Preview Mode", systemImage: state.previewMode ? "eye.fill" : "eye")
                }
                .toggleStyle(.button)
                .tint(.indigo)
                .help(state.previewMode
                    ? "Preview mode ON — rules show what they'd do but don't act"
                    : "Preview mode OFF — rules execute normally")
            }

            // ── Group D: FIND ────────────────────────────────────
            ToolbarItem(id: "search", placement: .automatic) {
                if selection == .watchers {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        TextField("Search rules", text: $ruleSearch)
                            .textFieldStyle(.plain)
                            .frame(width: 160)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.quinary)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            }

            // ── Group E: CONFIG ──────────────────────────────────
            ToolbarItem(id: "edit-config", placement: .automatic) {
                Button { state.openConfigInEditor() } label: {
                    Label("Edit Config", systemImage: "square.and.pencil")
                }
                .help("Open config.yaml in default editor")
            }
        }
        // Preview mode banner
        .safeAreaInset(edge: .top, spacing: 0) {
            if state.previewMode {
                previewBanner
            }
        }
    }

    // MARK: - Preview mode banner
    private var previewBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "eye.fill")
                .foregroundStyle(.white)
            Text("Preview Mode — rules show what they'd do but won't execute files")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundStyle(.white)
            Spacer()
            Button("Turn Off") { state.togglePreviewMode() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.white.opacity(0.18))
                .clipShape(Capsule())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(Color.indigo.gradient)
    }

    // MARK: - Detail view routing
    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .watchers, nil:
            if let w = state.selectedWatcher ?? state.config.watch.first {
                WatcherDetailView(watcher: w, ruleSearch: ruleSearch)
            } else {
                EmptyStateView()
            }
        case .activity:
            ActivityView()
        case .settings:
            SettingsView()
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject var state: AppState
    @Binding var selection: ContentView.SidebarItem?

    var body: some View {
        List(selection: $selection) {
            statusChip

            Section("Folders") {
                ForEach(state.config.watch) { watcher in
                    WatcherRow(watcher: watcher)
                        .tag(ContentView.SidebarItem.watchers)
                        .onTapGesture {
                            state.selectedWatcher = watcher
                            selection = .watchers
                        }
                }
            }

            Section {
                Label("Activity", systemImage: "list.bullet.rectangle.portrait")
                    .tag(ContentView.SidebarItem.activity)
                Label("Settings", systemImage: "gearshape")
                    .tag(ContentView.SidebarItem.settings)
            }
        }
        .listStyle(.sidebar)
    }

    private var statusChip: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().fill(state.isRunning ? Color.green.opacity(0.2) : Color.clear)
                    .frame(width: 16, height: 16)
                Circle().fill(state.isRunning ? Color.green : Color.gray.opacity(0.5))
                    .frame(width: 7, height: 7)
            }
            Text(state.previewMode ? "Preview" : state.isRunning ? "Watching" : "Paused")
                .font(.caption)
                .foregroundStyle(state.previewMode ? .indigo : state.isRunning ? .green : .secondary)
                .fontWeight(state.previewMode ? .semibold : .regular)
            Spacer()
            if state.previewMode {
                Image(systemName: "eye.fill")
                    .font(.caption2)
                    .foregroundStyle(.indigo)
            }
        }
        .padding(.vertical, 3)
    }
}

struct WatcherRow: View {
    let watcher: WatcherConfig
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: watcher.enabled ? "folder.fill" : "folder")
                .foregroundStyle(watcher.enabled ? .blue : .secondary)
                .imageScale(.medium)
            VStack(alignment: .leading, spacing: 1) {
                Text(watcher.name ?? shortPath(watcher.path))
                    .font(.body)
                    .lineLimit(1)
                    .foregroundStyle(watcher.enabled ? .primary : .secondary)
                Text("\(watcher.rules.filter(\.enabled).count)/\(watcher.rules.count) rules active  ·  \(shortPath(watcher.path))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }
    private func shortPath(_ p: String) -> String {
        p.replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
    }
}

struct EmptyStateView: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "folder.badge.gearshape")
                .font(.system(size: 72))
                .foregroundStyle(.indigo.gradient)
                .opacity(0.6)
            VStack(spacing: 6) {
                Text("No Folders Watched")
                    .font(.title2).fontWeight(.semibold)
                Text("Click  ⊞  in the toolbar to add your first folder,\nor open your config file to get started.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("Open Config in Editor") { state.openConfigInEditor() }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}
