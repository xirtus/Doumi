import SwiftUI
import DoumiCore

@main
struct DoumiMainApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        // Main preferences window
        WindowGroup("Doumi") {
            ContentView()
                .environmentObject(appState)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(after: .appSettings) {
                Button("Run Rules Now") { appState.runNow() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("Reload Config") { appState.restart() }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Toggle Preview Mode") { appState.togglePreviewMode() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Button("Edit Config in Editor") { appState.openConfigInEditor() }
                    .keyboardShortcut("e", modifiers: [.command, .shift])
            }
        }

        // Settings window — opened via Cmd+, or App menu → Settings
        Settings {
            SettingsView()
                .environmentObject(appState)
                .frame(minWidth: 480, minHeight: 360)
        }

        // Detached watcher window (opened via openWindow)
        WindowGroup("Watcher", id: "watcher-detail", for: String.self) { $watcherID in
            DetachedWatcherView(watcherID: watcherID ?? "")
                .environmentObject(appState)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 620, height: 540)

        // Menu bar item
        MenuBarExtra {
            MenuBarContent()
                .environmentObject(appState)
        } label: {
            Image(systemName: appState.previewMode
                  ? "eye.circle.fill"
                  : appState.isRunning ? "folder.badge.gearshape" : "folder.badge.gearshape")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(
                    appState.previewMode ? .indigo :
                    appState.isRunning   ? .primary : .secondary
                )
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Detached watcher window

struct DetachedWatcherView: View {
    let watcherID: String
    @EnvironmentObject var state: AppState

    var watcher: WatcherConfig? {
        state.config.watch.first { $0.id.uuidString == watcherID }
    }

    var body: some View {
        if let w = watcher {
            WatcherDetailView(watcher: w, ruleSearch: "")
        } else {
            Text("Folder not found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
