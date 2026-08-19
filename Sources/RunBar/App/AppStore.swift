import AppKit
import Foundation
import RunBarCore

@MainActor
@Observable
final class AppStore {
    var settings: AppSettings
    var authState: GhAuthState = .checking
    var snapshot = WorkflowSnapshot()
    var summary = ActivitySummary.empty
    var isRefreshing = false
    var isManualRefreshing = false
    var lastRefresh: Date?
    var errorMessage: String?
    var isPopoverOpen = false
    var isSleeping = false

    @ObservationIgnored
    private let settingsStore = SettingsStore()
    @ObservationIgnored
    private let client = GhClient()
    @ObservationIgnored
    private var pollingTask: Task<Void, Never>?
    @ObservationIgnored
    private var inFlightRefresh: Task<Void, Never>?
    @ObservationIgnored
    private var repositoryBrowserCache: RepositoryBrowserCache?

    var login: String? { authState.login }

    var subtitle: String {
        let repoCount = settings.repositories.count
        let repoLabel = "\(repoCount) repo\(repoCount == 1 ? "" : "s")"
        return "Watching \(repoLabel) · \(settings.watchRule.summaryLabel)"
    }

    init(settings: AppSettings? = nil, startAutomatically: Bool = true) {
        self.settings = settings ?? SettingsStore().load()
        if startAutomatically {
            observeSleep()
            Task { await start() }
        }
    }

    func start() async {
        await refreshAuth()
        await refresh()
        startPolling()
    }

    func popoverOpened() {
        isPopoverOpen = true
        startPolling()
        Task { await refresh() }
    }

    func popoverClosed() {
        isPopoverOpen = false
        startPolling()
    }

    func refreshAuth() async {
        authState = .checking
        authState = await client.authState()
        if case let .loggedOut(message) = authState, !message.isEmpty {
            errorMessage = message
        }
    }

    func refresh(userInitiated: Bool = false) async {
        if userInitiated {
            isManualRefreshing = true
        }

        if let inFlightRefresh {
            await inFlightRefresh.value
            if userInitiated {
                isManualRefreshing = false
            }
            return
        }

        let task = Task { @MainActor in
            await self.performRefresh(userInitiated: userInitiated)
        }
        inFlightRefresh = task
        await task.value
        inFlightRefresh = nil
    }

    func addRepository(_ repository: Repository) {
        guard !settings.repositories.contains(repository) else { return }
        settings.repositories.append(repository)
        persistAndRefresh()
    }

    func addRepository(from raw: String) throws {
        try addRepository(Repository.parse(raw))
    }

    func removeRepository(_ repository: Repository) {
        settings.repositories.removeAll { $0 == repository }
        settings.pins.removeAll { $0.repository == repository }
        persistAndRefresh()
    }

    func updateWatchRule(_ rule: WatchRule) {
        settings.watchRule = rule
        persistAndRefresh()
    }

    func addPin(_ pin: PinnedWorkflow) {
        guard !settings.pins.contains(pin) else { return }
        if !settings.repositories.contains(pin.repository) {
            settings.repositories.append(pin.repository)
        }
        settings.pins.append(pin)
        persistAndRefresh()
    }

    func removePin(_ pin: PinnedWorkflow) {
        settings.pins.removeAll { $0 == pin }
        persistAndRefresh()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        settings.launchAtLogin = enabled
        settingsStore.save(settings)
        do {
            try LaunchAtLogin.setEnabled(enabled)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func fetchRepositoryBrowserCatalog() async throws -> (repositories: [GitHubRepositorySummary], organizations: [String]) {
        if let cache = repositoryBrowserCache, cache.isFresh {
            return (cache.repositories, cache.organizations)
        }

        async let repositoryTask = client.listRepositories(limit: RepositoryCatalog.recentLimit)
        async let organizationTask = client.listOrganizations()
        let repositories = try await repositoryTask
        let organizations: [String]
        do {
            organizations = try await organizationTask
        } catch {
            organizations = []
        }
        rememberCatalog(repositories: repositories, organizations: organizations)
        return (repositories, organizations)
    }

    func fetchRepositories(ownedBy owner: String) async throws -> [GitHubRepositorySummary] {
        try await client.listRepositories(ownedBy: owner, limit: RepositoryCatalog.ownerLimit)
    }

    func searchRepositories(query: String, owners: [String]) async throws -> [GitHubRepositorySummary] {
        try await client.searchRepositories(
            query: query,
            owners: owners,
            limit: RepositoryCatalog.searchLimit
        )
    }

    func fetchWorkflows(in repository: Repository) async throws -> [GhWorkflowDTO] {
        try await client.listWorkflows(in: repository)
    }

    private func persistAndRefresh() {
        settingsStore.save(settings)
        Task { await refresh() }
    }

    private func rememberCatalog(repositories: [GitHubRepositorySummary], organizations: [String]) {
        repositoryBrowserCache = RepositoryBrowserCache(
            repositories: repositories,
            organizations: organizations,
            fetchedAt: .now
        )
    }

    private func performRefresh(userInitiated: Bool) async {
        defer {
            isRefreshing = false
            if userInitiated {
                isManualRefreshing = false
            }
        }

        if isSleeping {
            return
        }

        switch authState {
        case .missingCLI, .loggedOut:
            snapshot = WorkflowSnapshot()
            summary = .empty
            return
        case .checking:
            authState = await client.authState()
        case .ready:
            break
        }

        guard authState.isReady else {
            snapshot = WorkflowSnapshot()
            summary = .empty
            return
        }

        if settings.repositories.isEmpty && settings.pins.isEmpty {
            snapshot = WorkflowSnapshot()
            summary = .empty
            lastRefresh = .now
            errorMessage = nil
            return
        }

        isRefreshing = true
        errorMessage = nil
        let fetched = await client.fetchSnapshot(
            repositories: settings.repositories,
            pins: settings.pins,
            rule: settings.watchRule,
            login: login,
            runsPerRepo: settings.runsPerRepo,
            pinnedRunsLimit: settings.pinnedRunsLimit
        )
        snapshot = fetched
        summary = ActivitySummary(runs: uniqueRuns(from: fetched), pins: fetched.pinned)
        lastRefresh = fetched.fetchedAt
        if !fetched.warnings.isEmpty {
            errorMessage = fetched.warnings.prefix(2).joined(separator: " · ")
        }
    }

    private func uniqueRuns(from snapshot: WorkflowSnapshot) -> [WorkflowRun] {
        var seen = Set<String>()
        var runs: [WorkflowRun] = []
        for run in snapshot.pinned.compactMap(\.latestRun) + snapshot.activeRuns + snapshot.groups.flatMap(\.runs) {
            if seen.insert(run.id).inserted {
                runs.append(run)
            }
        }
        return runs
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = PollingPolicy.intervalSeconds(
                    popoverOpen: self.isPopoverOpen,
                    hasActiveRuns: self.summary.activeRunCount > 0,
                    isSleeping: self.isSleeping
                )
                let delay = interval ?? PollingPolicy.sleepCheckInterval
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                if interval != nil {
                    await self.refresh()
                }
            }
        }
    }

    private func observeSleep() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isSleeping = true
                self?.startPolling()
            }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.isSleeping = false
                self?.startPolling()
                await self?.refresh()
            }
        }
    }
}

private struct RepositoryBrowserCache {
    var repositories: [GitHubRepositorySummary]
    var organizations: [String]
    var fetchedAt: Date

    var isFresh: Bool {
        Date.now.timeIntervalSince(fetchedAt) < 5 * 60
    }
}
