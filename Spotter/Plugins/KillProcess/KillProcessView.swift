import SwiftUI

struct KillProcessView: View {
    @ObservedObject var manager: KillProcessManager
    @State private var query = ""
    @State private var selection: Int32?
    @AppStorage("kill-process.sort") private var sortRaw = ProcessSort.cpu.rawValue
    @AppStorage("kill-process.group-apps") private var groupApps = true
    @AppStorage("kill-process.search-paths") private var searchPaths = false
    @AppStorage("kill-process.search-pids") private var searchPIDs = true
    @AppStorage("kill-process.prioritize-apps") private var prioritizeApps = true
    @AppStorage("kill-process.show-path") private var showPath = false
    @AppStorage("kill-process.show-pid") private var showPID = true
    @AppStorage("kill-process.confirm") private var confirmActions = true
    @AppStorage("kill-process.refresh-seconds") private var refreshSeconds = 2.0

    private var sort: ProcessSort { ProcessSort(rawValue: sortRaw) ?? .cpu }
    private var visible: [RunningProcessInfo] {
        KillProcessEngine.visible(
            manager.processes, query: query, sort: sort, groupingApplications: groupApps,
            searchPaths: searchPaths, searchPIDs: searchPIDs, prioritizeApps: prioritizeApps)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = manager.errorMessage {
                ContentUnavailableView(
                    "Failed to Fetch Processes", systemImage: "exclamationmark.triangle",
                    description: Text(error))
            } else if visible.isEmpty, !manager.isRefreshing {
                ContentUnavailableView.search(text: query)
            } else {
                processList
            }
        }
        .background(VisualEffectView(material: .contentBackground, blending: .behindWindow))
        .ignoresSafeArea(edges: .top)
        .task {
            while !Task.isCancelled {
                await manager.refresh()
                try? await Task.sleep(for: .seconds(max(0.5, refreshSeconds)))
            }
        }
    }

    private var header: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Filter by name, path, or PID…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                if manager.isRefreshing { ProgressView().controlSize(.small) }
                Picker("Sort", selection: $sortRaw) {
                    ForEach(ProcessSort.allCases, id: \.rawValue) { value in
                        Text(value.title).tag(value.rawValue)
                    }
                }
                .labelsHidden()
                .frame(width: 140)
                Button { Task { await manager.refresh() } } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
            }
            HStack {
                Text("\(visible.count) running")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Toggle("Group Applications", isOn: $groupApps)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
        }
        .padding(Theme.Spacing.xxl)
        .padding(.top, Theme.Spacing.xl)
    }

    private var processList: some View {
        List(visible, selection: $selection) { process in
            ProcessRow(
                process: process, showPID: showPID, showPath: showPath,
                onAction: { action in perform(action, on: process) })
                .tag(process.id)
        }
        .listStyle(.inset)
    }

    private func perform(_ action: ProcessRow.Action, on process: RunningProcessInfo) {
        let force = action == .forceKill || action == .forceRestart || action == .forceKillAll
        let actionTitle: String
        switch action {
        case .kill, .forceKill: actionTitle = force ? "Force Kill" : "Kill"
        case .restart, .forceRestart: actionTitle = force ? "Force Restart" : "Restart"
        case .killAll, .forceKillAll: actionTitle = force ? "Force Kill All" : "Kill All"
        case .copyPath:
            Paster.copyPlainText(process.executablePath)
            return
        }
        guard !confirmActions || confirm(actionTitle, process: process) else { return }
        Task {
            do {
                switch action {
                case .kill, .forceKill:
                    try await manager.terminate(process, force: force)
                case .restart, .forceRestart:
                    try await manager.restart(process, force: force)
                case .killAll, .forceKillAll:
                    try await manager.terminateAll(named: process.processName, force: force)
                case .copyPath:
                    break
                }
            } catch {
                presentFailure(actionTitle, error: error)
            }
        }
    }

    private func confirm(_ action: String, process: RunningProcessInfo) -> Bool {
        let alert = NSAlert()
        alert.messageText = "\(action) \(process.processName)?"
        alert.informativeText = "PID \(process.id)" +
            (process.childProcessIDs.isEmpty ? "" : " and \(process.childProcessIDs.count) related processes")
        alert.alertStyle = .warning
        let actionButton = alert.addButton(withTitle: action)
        actionButton.hasDestructiveAction = true
        actionButton.keyEquivalent = ""
        alert.addButton(withTitle: "Cancel").keyEquivalent = "\r"
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func presentFailure(_ action: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = "\(action) Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}

private struct ProcessRow: View {
    enum Action { case kill, forceKill, restart, forceRestart, killAll, forceKillAll, copyPath }
    let process: RunningProcessInfo
    let showPID: Bool
    let showPath: Bool
    let onAction: (Action) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(nsImage: icon)
                .resizable()
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(process.processName).lineLimit(1)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Spacing.xl)
            Label(process.cpu.formatted(.number.precision(.fractionLength(2))) + "%", systemImage: "cpu")
            Label(ByteCountFormatter.string(fromByteCount: process.memoryKB * 1024, countStyle: .memory), systemImage: "memorychip")
            Menu {
                Button("Kill") { onAction(.kill) }
                Button("Force Kill") { onAction(.forceKill) }
                if process.canRestart {
                    Button("Restart") { onAction(.restart) }
                    Button("Force Restart") { onAction(.forceRestart) }
                }
                Divider()
                Button("Kill All \(process.processName)") { onAction(.killAll) }
                Button("Force Kill All \(process.processName)") { onAction(.forceKillAll) }
                if !process.executablePath.isEmpty {
                    Divider()
                    Button("Copy Path") { onAction(.copyPath) }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .font(.callout)
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var subtitle: String {
        var parts: [String] = []
        if process.kind == .aggregatedApp { parts.append("\(process.childProcessIDs.count + 1) processes") }
        if showPID { parts.append("PID \(process.id)") }
        if showPath { parts.append(process.executablePath) }
        return parts.joined(separator: " · ")
    }

    private var icon: NSImage {
        if let bundle = process.appBundlePath { return IconCache.icon(forFile: bundle) }
        return IconCache.symbolIcon(named: "terminal")
    }
}
