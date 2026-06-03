import SwiftUI
import DoumiCore

struct ActivityView: View {
    @EnvironmentObject var state: AppState
    @State private var searchText = ""
    @State private var filterLevel: FilterLevel = .all

    enum FilterLevel: String, CaseIterable {
        case all = "All"
        case actions = "Actions"
        case errors = "Errors"
    }

    private var filtered: [LogEntry] {
        state.activityLog.filter { entry in
            let matchesSearch = searchText.isEmpty ||
                entry.message.localizedCaseInsensitiveContains(searchText)
            let matchesLevel: Bool
            switch filterLevel {
            case .all: matchesLevel = true
            case .actions:
                matchesLevel = entry.message.contains("MOVE") || entry.message.contains("RENAME") ||
                    entry.message.contains("COPY") || entry.message.contains("DELETE") ||
                    entry.message.contains("TRASH") || entry.message.contains("RUN")
            case .errors:
                matchesLevel = entry.message.lowercased().contains("error") ||
                    entry.message.lowercased().contains("warn")
            }
            return matchesSearch && matchesLevel
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            if filtered.isEmpty {
                emptyState
            } else {
                logList
            }
        }
        .navigationTitle("Activity")
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search logs…", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.body)
            }
            .padding(6)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(NSColor.separatorColor), lineWidth: 0.5))

            Picker("Filter", selection: $filterLevel) {
                ForEach(FilterLevel.allCases, id: \.self) { level in
                    Text(level.rawValue).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Spacer()

            Button("Clear") { state.activityLog.removeAll() }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)
                .disabled(state.activityLog.isEmpty)
        }
        .padding(12)
        .background(.bar)
    }

    private var logList: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(filtered) { entry in
                    LogEntryRow(entry: entry)
                }
            }
            .padding(10)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(state.isRunning ? "Waiting for file events…" : "Doumi is not running")
                .font(.title3)
                .foregroundStyle(.secondary)
            if !state.isRunning {
                Button("Start Watching") { state.startWatching() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.actionIcon)
                .font(.caption)
                .foregroundStyle(iconColor)
                .frame(width: 16, height: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(cleanMessage(entry.message))
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                Text(relativeTime(entry.date))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(rowBackground)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var iconColor: Color {
        let m = entry.message.lowercased()
        if m.contains("error") { return .red }
        if m.contains("warn")  { return .orange }
        if m.contains("move") || m.contains("rename") || m.contains("copy") { return .blue }
        if m.contains("trash") || m.contains("delete") { return .red.opacity(0.7) }
        if m.contains("notify") { return .purple }
        return .secondary
    }

    private var rowBackground: Color {
        let m = entry.message.lowercased()
        if m.contains("error") { return Color.red.opacity(0.05) }
        if m.contains("warn")  { return Color.orange.opacity(0.05) }
        return Color.clear
    }

    private func cleanMessage(_ msg: String) -> String {
        // Strip timestamp prefix "[HH:mm:ss]      "
        if let range = msg.range(of: #"^\[\d{2}:\d{2}:\d{2}\]\s+"#, options: .regularExpression) {
            return String(msg[range.upperBound...])
        }
        return msg
    }

    private func relativeTime(_ date: Date) -> String {
        let diff = Date().timeIntervalSince(date)
        if diff < 10   { return "just now" }
        if diff < 60   { return "\(Int(diff))s ago" }
        if diff < 3600 { return "\(Int(diff/60))m ago" }
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return f.string(from: date)
    }
}
