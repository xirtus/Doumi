import SwiftUI
import DoumiCore

struct MenuBarContent: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "folder.badge.gearshape")
                    .foregroundStyle(.indigo)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Doumi")
                        .font(.headline)
                    Text(state.isRunning
                         ? "Watching \(state.config.watch.filter(\.enabled).count) folder(s)"
                         : "Stopped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(state.isRunning ? Color.green : Color.gray)
                    .frame(width: 8, height: 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            // Recent activity (last 3 entries)
            if !state.activityLog.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Recent")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.top, 6)

                    ForEach(state.activityLog.prefix(3)) { entry in
                        HStack(spacing: 6) {
                            Image(systemName: entry.actionIcon)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                            Text(cleanMessage(entry.message))
                                .font(.caption)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                    }
                }
                Divider()
            }

            // Actions
            Button("Open Doumi") {
                NSApp.activate(ignoringOtherApps: true)
            }
            .buttonStyle(MenuBarButtonStyle())

            Button("Run Rules Now") {
                state.runNow()
            }
            .buttonStyle(MenuBarButtonStyle())

            Button(state.isRunning ? "Pause Watching" : "Resume Watching") {
                if state.isRunning { state.stopWatching() } else { state.restart() }
            }
            .buttonStyle(MenuBarButtonStyle())

            Button("Edit Config") { state.openConfigInEditor() }
                .buttonStyle(MenuBarButtonStyle())

            Divider()

            Button("Quit Doumi") { NSApp.terminate(nil) }
                .buttonStyle(MenuBarButtonStyle())
        }
        .frame(width: 260)
    }

    private func cleanMessage(_ msg: String) -> String {
        if let m = msg.firstMatch(of: /^\[\d{2}:\d{2}:\d{2}\]\s+/) {
            return String(msg[m.range.upperBound...])
        }
        return msg
    }
}

struct MenuBarButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(configuration.isPressed ? Color(NSColor.selectedContentBackgroundColor) : .clear)
    }
}
