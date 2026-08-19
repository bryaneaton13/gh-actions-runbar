import AppKit
import RunBarCore
import SwiftUI

struct MenuBarPanel: View {
    private enum WindowID {
        static let settings = "settings"
    }

    @Environment(\.openWindow) private var openWindow
    let store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 380)
        .background(.regularMaterial)
        .onAppear { store.popoverOpened() }
        .onDisappear { store.popoverClosed() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: store.summary.symbolName)
                .font(.title3)
                .foregroundStyle(store.summary.usesFailureTint ? RunBarTheme.failure : RunBarTheme.inProgress)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(store.summary.headline)
                    .font(.headline)
                    .lineLimit(1)
                Text(headerSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HeaderActionButton(
                systemName: "arrow.clockwise",
                helpText: "Refresh now",
                isBusy: store.isManualRefreshing
            ) {
                Task { await store.refresh(userInitiated: true) }
            }

            HeaderActionButton(systemName: "gearshape", helpText: "Open Settings") {
                openSettings()
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var headerSubtitle: String {
        switch store.authState {
        case .checking:
            return "Checking gh…"
        case .missingCLI:
            return "GitHub CLI is missing"
        case .loggedOut:
            return "gh is not signed in"
        case let .ready(login):
            return "\(store.subtitle) · \(login)"
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.authState {
        case .checking:
            StatusCard(
                symbol: "ellipsis.circle",
                title: "Connecting",
                message: "Checking the GitHub CLI session."
            )
            .frame(minHeight: 180)
        case .missingCLI:
            SetupCard(
                symbol: "terminal",
                title: "Install the GitHub CLI",
                message: "RunBar uses gh to load workflow runs. Install it, then refresh.",
                command: "brew install gh"
            )
            .padding(16)
        case .loggedOut:
            SetupCard(
                symbol: "person.badge.key",
                title: "Sign in with gh",
                message: "Authorize the GitHub CLI in Terminal, then come back here.",
                command: "gh auth login"
            )
            .padding(16)
        case .ready:
            if store.settings.repositories.isEmpty && store.settings.pins.isEmpty {
                EmptyRepositoriesView(openSettings: openSettings)
                    .frame(minHeight: 180)
            } else {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 16) {
                            if !store.snapshot.pinned.isEmpty {
                                PinnedSection(
                                    pins: store.snapshot.pinned,
                                    failureCount: store.summary.pinnedFailureCount,
                                    referenceDate: context.date
                                )
                            }

                            if !store.snapshot.activeRuns.isEmpty {
                                ActiveSection(runs: store.snapshot.activeRuns, referenceDate: context.date)
                            }

                            if store.snapshot.groups.isEmpty
                                && store.snapshot.activeRuns.isEmpty
                                && store.snapshot.pinned.allSatisfy({ $0.latestRun == nil })
                            {
                                EmptyMatchingView()
                            } else {
                                ForEach(store.snapshot.groups) { group in
                                    RepositorySection(group: group, referenceDate: context.date)
                                }
                            }
                        }
                        .padding(16)
                    }
                    .frame(minHeight: 380, maxHeight: 560)
                    .transaction { $0.animation = nil }
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let errorMessage = store.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
                    .lineLimit(2)
            }

            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(lastRefreshText(referenceDate: context.date))
                }
                Text("·")
                Text(ghFooterLabel)
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 14) {
                FooterLink(title: "Settings", systemName: "gearshape", action: openSettings)
                FooterLink(title: "Website", systemName: "safari") {
                    NSWorkspace.shared.open(AppInfo.websiteURL)
                }
                FooterLink(title: "GitHub", systemName: "arrow.up.right.square") {
                    NSWorkspace.shared.open(AppInfo.githubURL)
                }
                Spacer(minLength: 0)
                FooterLink(title: "Quit", systemName: "power") {
                    NSApp.terminate(nil)
                }
            }
            .font(.caption)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var ghFooterLabel: String {
        switch store.authState {
        case .ready:
            return "gh ok"
        case .missingCLI:
            return "gh missing"
        case .loggedOut:
            return "gh signed out"
        case .checking:
            return "gh…"
        }
    }

    private func lastRefreshText(referenceDate: Date) -> String {
        guard let lastRefresh = store.lastRefresh else {
            return "Not refreshed yet"
        }
        return "Updated \(RelativeTime.description(of: lastRefresh, relativeTo: referenceDate))"
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: WindowID.settings)
    }
}

private struct HeaderActionButton: View {
    let systemName: String
    let helpText: String
    var isBusy: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                } else {
                    Image(systemName: systemName)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
            )
            .contentShape(Rectangle())
            .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .disabled(isBusy)
        .help(helpText)
        .accessibilityLabel(helpText)
        .accessibilityValue(isBusy ? "Refreshing" : "")
        .accessibilityAddTraits(.isButton)
    }
}

private struct FooterLink: View {
    let title: String
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemName)
                Text(title)
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct PinnedSection: View {
    let pins: [PinSnapshot]
    var failureCount: Int = 0
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(
                title: "Pinned",
                systemName: failureCount > 0 ? "exclamationmark.circle.fill" : "pin.fill",
                count: pins.count,
                tinted: failureCount > 0,
                tint: failureCount > 0 ? RunBarTheme.failure : nil
            )
            VStack(spacing: 8) {
                ForEach(pins) { pin in
                    PinRow(snapshot: pin, referenceDate: referenceDate)
                }
            }
        }
    }
}

private struct ActiveSection: View {
    let runs: [WorkflowRun]
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title: "Active", systemName: "bolt.fill", count: runs.count, tinted: true, tint: RunBarTheme.inProgress)
            VStack(spacing: 8) {
                ForEach(runs) { run in
                    RunRow(run: run, referenceDate: referenceDate, repositoryLabel: run.repository.fullName)
                }
            }
        }
    }
}

private struct RepositorySection: View {
    let group: RepositoryRunGroup
    let referenceDate: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(group.repository.fullName)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
                Button {
                    if let url = URL(string: "https://github.com/\(group.repository.fullName)/actions") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "arrow.up.right.square")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open Actions on GitHub")
            }

            VStack(spacing: 8) {
                ForEach(group.runs) { run in
                    RunRow(run: run, referenceDate: referenceDate, compact: true)
                }
            }
        }
    }
}

private struct SectionLabel: View {
    let title: String
    let systemName: String
    var count: Int = 0
    var tinted: Bool = false
    var tint: Color? = nil

    private var accent: Color {
        tint ?? (tinted ? RunBarTheme.inProgress : Color.secondary)
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemName)
                .font(.caption)
                .foregroundStyle(accent)
            Text(title)
                .font(.subheadline.weight(.semibold))
            if count > 0 {
                Text("\(count)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(accent.opacity(0.18)))
                    .foregroundStyle(accent)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct StatusCard: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.subheadline.weight(.semibold))
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
    }
}

private struct SetupCard: View {
    let symbol: String
    let title: String
    let message: String
    let command: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(RunBarTheme.inProgress)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Text(command)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(copied ? "Copied" : "Copy")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(copied ? RunBarTheme.success : .secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.4))
            )
            .contentShape(Rectangle())
            .onTapGesture {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
            .help(copied ? "Copied" : "Click to copy")
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(copied ? "Copied \(command)" : "Copy \(command)")
        }
    }
}

private struct EmptyRepositoriesView: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            VStack(spacing: 4) {
                Text("No repositories yet")
                    .font(.subheadline.weight(.semibold))
                Text("Add the repos whose Actions you want to watch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button(action: openSettings) {
                Label("Add Repository", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(RunBarTheme.inProgress)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
    }
}

private struct EmptyMatchingView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No matching runs")
                .font(.subheadline.weight(.semibold))
            Text("Nothing in the last batch matched your filters. Pinned workflows still appear above when they have history.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary.opacity(0.25))
        )
    }
}
