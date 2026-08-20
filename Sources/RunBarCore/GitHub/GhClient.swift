import Foundation

public struct WorkflowSnapshot: Sendable, Equatable {
    public var pinned: [PinSnapshot]
    public var groups: [RepositoryRunGroup]
    public var activeRuns: [WorkflowRun]
    public var typicalDurations: [String: TimeInterval]
    public var fetchedAt: Date
    public var warnings: [String]

    public init(
        pinned: [PinSnapshot] = [],
        groups: [RepositoryRunGroup] = [],
        activeRuns: [WorkflowRun] = [],
        typicalDurations: [String: TimeInterval] = [:],
        fetchedAt: Date = .now,
        warnings: [String] = []
    ) {
        self.pinned = pinned
        self.groups = groups
        self.activeRuns = activeRuns
        self.typicalDurations = typicalDurations
        self.fetchedAt = fetchedAt
        self.warnings = warnings
    }

    public func typicalDuration(for run: WorkflowRun) -> TimeInterval? {
        typicalDurations[TypicalDuration.key(for: run)]
    }

    public var allRuns: [WorkflowRun] {
        pinned.flatMap(\.runs) + groups.flatMap(\.runs) + activeRuns
    }

    public var isEmpty: Bool {
        pinned.allSatisfy { $0.latestRun == nil } && groups.isEmpty && activeRuns.isEmpty
    }
}

public struct GitHubRepositorySummary: Identifiable, Hashable, Sendable {
    public let repository: Repository
    public let description: String?
    public let isPrivate: Bool
    public let isFork: Bool
    public let updatedAt: Date?

    public init(
        repository: Repository,
        description: String? = nil,
        isPrivate: Bool = false,
        isFork: Bool = false,
        updatedAt: Date? = nil
    ) {
        self.repository = repository
        self.description = description
        self.isPrivate = isPrivate
        self.isFork = isFork
        self.updatedAt = updatedAt
    }

    public var id: String { repository.id }
    public var fullName: String { repository.fullName }
}

private let runJSONFields = [
    "databaseId",
    "workflowName",
    "displayTitle",
    "status",
    "conclusion",
    "event",
    "headBranch",
    "headSha",
    "name",
    "createdAt",
    "startedAt",
    "updatedAt",
    "url",
].joined(separator: ",")

public struct GhClient: Sendable {
    public static let maxConcurrency = 6

    private let process: any GhRunning

    public init(process: any GhRunning = GhProcess()) {
        self.process = process
    }

    public func authState() async -> GhAuthState {
        guard GhExecutable.resolve() != nil else {
            return .missingCLI
        }

        do {
            _ = try await process.run(["auth", "status"])
            let login = try await currentLogin()
            return .ready(login: login)
        } catch GhError.notFound {
            return .missingCLI
        } catch let GhError.unauthenticated(message) {
            return .loggedOut(message)
        } catch let GhError.failed(_, message) {
            return .loggedOut(message)
        } catch {
            return .loggedOut(error.localizedDescription)
        }
    }

    public func currentLogin() async throws -> String {
        let output = try await process.run(["api", "user", "--jq", ".login"])
        let login = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !login.isEmpty else {
            throw GhError.unauthenticated("Could not read the signed-in GitHub user.")
        }
        return login
    }

    public func listRepositories(limit: Int = RepositoryCatalog.recentLimit) async throws -> [GitHubRepositorySummary] {
        do {
            return try await listAccessibleRepositories(limit: limit)
        } catch {
            return try await listRepositories(ownedBy: nil, limit: min(limit, RepositoryCatalog.recentLimit))
        }
    }

    public func listOrganizations() async throws -> [String] {
        let output = try await process.run([
            "api",
            "user/orgs?per_page=100",
        ])
        if output.isEmpty || output == "[]" { return [] }
        do {
            let payload = try GitHubJSON.decoder().decode([GhOrgDTO].self, from: Data(output.utf8))
            return payload.map(\.login).filter { !$0.isEmpty }
        } catch {
            throw GhError.decoding(error.localizedDescription)
        }
    }

    public func listAccessibleRepositories(limit: Int = RepositoryCatalog.recentLimit) async throws -> [GitHubRepositorySummary] {
        let perPage = min(100, max(limit, 1))
        let maxPages = max(1, Int(ceil(Double(max(limit, 1)) / Double(perPage))))
        var collected: [GitHubRepositorySummary] = []
        var seen = Set<String>()

        for page in 1...maxPages {
            let output = try await process.run([
                "api",
                "user/repos?per_page=\(perPage)&page=\(page)&affiliation=owner,collaborator,organization_member&sort=updated&direction=desc",
            ])
            if output.isEmpty || output == "[]" { break }

            let payload: [GhAccessibleRepoDTO]
            do {
                payload = try GitHubJSON.decoder().decode([GhAccessibleRepoDTO].self, from: Data(output.utf8))
            } catch {
                throw GhError.decoding(error.localizedDescription)
            }
            if payload.isEmpty { break }

            for dto in payload {
                guard dto.archived != true else { continue }
                guard let summary = try? dto.summary() else { continue }
                if seen.insert(summary.id).inserted {
                    collected.append(summary)
                    if collected.count >= limit { return collected }
                }
            }

            if payload.count < perPage { break }
        }

        return collected
    }

    public func listRepositories(ownedBy owner: String?, limit: Int = RepositoryCatalog.ownerLimit) async throws -> [GitHubRepositorySummary] {
        var arguments = ["repo", "list"]
        if let owner, !owner.isEmpty {
            arguments.append(owner)
        }
        arguments.append(contentsOf: [
            "--limit", String(max(limit, 1)),
            "--no-archived",
            "--json", "nameWithOwner,description,isPrivate,isFork,updatedAt",
        ])
        let output = try await process.run(arguments)
        if output.isEmpty { return [] }
        do {
            let payload = try GitHubJSON.decoder().decode([GhRepoDTO].self, from: Data(output.utf8))
            return try payload.map { try $0.summary() }
        } catch let error as GhError {
            throw error
        } catch {
            throw GhError.decoding(error.localizedDescription)
        }
    }

    public func searchRepositories(
        query: String,
        owners: [String],
        limit: Int = RepositoryCatalog.searchLimit
    ) async throws -> [GitHubRepositorySummary] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        var arguments = [
            "search", "repos",
            "--limit", String(max(limit, 1)),
            "--json", "fullName,description,isPrivate,isFork,isArchived,updatedAt",
        ]
        var seenOwners = Set<String>()
        for owner in owners {
            let trimmedOwner = owner.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedOwner.isEmpty else { continue }
            guard seenOwners.insert(trimmedOwner.lowercased()).inserted else { continue }
            arguments.append(contentsOf: ["--owner", trimmedOwner])
            if seenOwners.count >= 15 { break }
        }
        arguments.append("archived:false \(trimmed)")

        let output = try await process.run(arguments)
        if output.isEmpty { return [] }
        do {
            let payload = try GitHubJSON.decoder().decode([GhSearchRepoDTO].self, from: Data(output.utf8))
            return payload.compactMap { dto in
                guard dto.isArchived != true else { return nil }
                return try? dto.summary()
            }
        } catch {
            throw GhError.decoding(error.localizedDescription)
        }
    }

    public func latestRelease(in repository: Repository) async throws -> AppRelease {
        guard repository.isValid else {
            throw GhError.failed(code: 1, message: "Invalid repository.")
        }
        let output = try await process.run([
            "release", "view",
            "--repo", repository.fullName,
            "--json", "tagName,url",
        ])
        do {
            let payload = try GitHubJSON.decoder().decode(GhReleaseDTO.self, from: Data(output.utf8))
            return try payload.appRelease()
        } catch let error as GhError {
            throw error
        } catch {
            throw GhError.decoding(error.localizedDescription)
        }
    }

    public func listWorkflows(in repository: Repository) async throws -> [GhWorkflowDTO] {
        guard repository.isValid else {
            throw GhError.failed(code: 1, message: "Invalid repository.")
        }
        let output = try await process.run([
            "workflow", "list",
            "-R", repository.fullName,
            "--all",
            "--json", "name,path,state",
        ])
        if output.isEmpty { return [] }
        do {
            return try GitHubJSON.decoder().decode([GhWorkflowDTO].self, from: Data(output.utf8))
        } catch {
            throw GhError.decoding(error.localizedDescription)
        }
    }

    public func rerun(run: WorkflowRun, failedOnly: Bool = false) async throws {
        try requireValid(run.repository)
        guard isRunID(run.id) else {
            throw GhError.failed(code: 1, message: "Invalid run id.")
        }
        var arguments = ["run", "rerun", run.id, "-R", run.repository.fullName]
        if failedOnly {
            arguments.append("--failed")
        }
        _ = try await process.run(arguments)
    }

    public func cancel(run: WorkflowRun) async throws {
        try requireValid(run.repository)
        guard isRunID(run.id) else {
            throw GhError.failed(code: 1, message: "Invalid run id.")
        }
        _ = try await process.run([
            "run", "cancel", run.id, "-R", run.repository.fullName,
        ])
    }

    public func dispatchWorkflow(
        named name: String,
        in repository: Repository,
        ref: String,
        inputs: [(String, String)] = []
    ) async throws {
        try requireValid(repository)
        guard WorkflowName.isValid(name) else {
            throw GhError.failed(code: 1, message: "Invalid workflow name.")
        }
        guard let ref = GitRef.parse(ref) else {
            throw GhError.failed(code: 1, message: "Invalid branch.")
        }
        var arguments = [
            "workflow", "run", name,
            "-R", repository.fullName,
            "--ref", ref,
        ]
        for (key, value) in inputs {
            guard WorkflowInputName.isValid(key) else { continue }
            arguments.append(contentsOf: ["-f", "\(key)=\(value)"])
        }
        _ = try await process.run(arguments)
    }

    public func workflowDispatchContext(
        for pin: PinnedWorkflow,
        ref: String? = nil
    ) async throws -> WorkflowDispatchContext {
        try requireValid(pin.repository)
        guard WorkflowName.isValid(pin.workflowName) else {
            throw GhError.failed(code: 1, message: "Invalid workflow name.")
        }

        async let defaultBranchTask = defaultBranch(in: pin.repository)
        async let branchesTask = listBranches(in: pin.repository)
        async let workflowsTask = listWorkflows(in: pin.repository)

        let defaultBranch = try await defaultBranchTask
        let branches = (try? await branchesTask) ?? [defaultBranch]
        let workflows = (try? await workflowsTask) ?? []
        let selectedRef = GitRef.parse(ref ?? "") ?? defaultBranch
        let yaml = try await workflowYAML(
            named: pin.workflowName,
            in: pin.repository,
            ref: selectedRef
        )
        var spec = WorkflowDispatchParser.parse(yaml)
        let environments: [String]
        if spec.needsEnvironments {
            environments = (try? await listEnvironments(in: pin.repository)) ?? []
            spec.inputs = spec.inputs.map { input in
                guard input.type == .environment else { return input }
                var copy = input
                if copy.options.isEmpty {
                    copy.options = environments
                }
                return copy
            }
        } else {
            environments = []
        }

        let path = workflows.first { $0.name == pin.workflowName }?.path
        var orderedBranches = branches
        if !orderedBranches.contains(defaultBranch) {
            orderedBranches.insert(defaultBranch, at: 0)
        }
        if let selectedRef = GitRef.parse(ref ?? ""), !orderedBranches.contains(selectedRef) {
            orderedBranches.insert(selectedRef, at: 0)
        }

        return WorkflowDispatchContext(
            pin: pin,
            spec: spec,
            defaultBranch: defaultBranch,
            branches: orderedBranches,
            environments: environments,
            workflowPath: path
        )
    }

    public func defaultBranch(in repository: Repository) async throws -> String {
        try requireValid(repository)
        let output = try await process.run([
            "api",
            "repos/\(repository.fullName)",
            "--jq",
            ".default_branch",
        ])
        guard let branch = GitRef.parse(output) else {
            throw GhError.decoding("Could not read the default branch.")
        }
        return branch
    }

    public func listBranches(in repository: Repository) async throws -> [String] {
        try requireValid(repository)
        let output = try await process.run([
            "api",
            "repos/\(repository.fullName)/branches?per_page=100",
        ])
        if output.isEmpty || output == "[]" { return [] }
        do {
            let payload = try GitHubJSON.decoder().decode([GhBranchDTO].self, from: Data(output.utf8))
            return payload.compactMap { GitRef.parse($0.name) }
        } catch {
            throw GhError.decoding(error.localizedDescription)
        }
    }

    public func listEnvironments(in repository: Repository) async throws -> [String] {
        try requireValid(repository)
        let output = try await process.run([
            "api",
            "repos/\(repository.fullName)/environments?per_page=100",
        ])
        if output.isEmpty || output == "{}" || output == "[]" { return [] }
        do {
            let payload = try GitHubJSON.decoder().decode(GhEnvironmentsPageDTO.self, from: Data(output.utf8))
            return (payload.environments ?? []).map(\.name).filter { !$0.isEmpty }
        } catch {
            throw GhError.decoding(error.localizedDescription)
        }
    }

    public func workflowYAML(named name: String, in repository: Repository, ref: String) async throws -> String {
        try requireValid(repository)
        guard WorkflowName.isValid(name) else {
            throw GhError.failed(code: 1, message: "Invalid workflow name.")
        }
        guard let ref = GitRef.parse(ref) else {
            throw GhError.failed(code: 1, message: "Invalid branch.")
        }
        return try await process.run([
            "workflow", "view", name,
            "-R", repository.fullName,
            "--yaml",
            "--ref", ref,
        ])
    }

    private func requireValid(_ repository: Repository) throws {
        guard repository.isValid else {
            throw GhError.failed(code: 1, message: "Invalid repository.")
        }
    }

    private func isRunID(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0.isASCII && $0.isNumber }
    }

    public func fetchSnapshot(
        repositories: [Repository],
        pins: [PinnedWorkflow],
        rule: WatchRule,
        login: String?,
        runsPerRepo: Int,
        pinsIncludeAllActors: Bool = true
    ) async -> WorkflowSnapshot {
        let stampedActor = rule.onlyMyRuns ? login : nil
        let includeEveryoneOnPins = pinsIncludeAllActors || !rule.onlyMyRuns
        let pinUser = includeEveryoneOnPins ? nil : login
        var warnings: [String] = []

        async let repoTask = throttledMap(repositories, concurrency: Self.maxConcurrency) { repository in
            await self.fetchRuns(
                repository: repository,
                user: rule.onlyMyRuns ? login : nil,
                workflow: nil,
                limit: runsPerRepo,
                actorStamp: stampedActor,
                status: nil
            )
        }
        async let pinTask = throttledMap(pins, concurrency: Self.maxConcurrency) { pin in
            await self.fetchRuns(
                repository: pin.repository,
                user: pinUser,
                workflow: pin.workflowName,
                limit: 1,
                actorStamp: pinUser,
                status: nil
            )
        }

        let repoResults = await repoTask
        let pinResults = await pinTask

        var filtered: [WorkflowRun] = []
        for (repository, result) in zip(repositories, repoResults) {
            switch result {
            case let .success(runs):
                filtered.append(contentsOf: runs.filter { RunFilter.matches($0, rule: rule, login: login) })
            case let .failure(error):
                warnings.append("\(repository.fullName): \(error.localizedDescription)")
            }
        }

        var actorLoginsByRepo: [String: [String: String]] = [:]
        if includeEveryoneOnPins {
            var seenRepos: [Repository] = []
            var seenIDs = Set<String>()
            for pin in pins where seenIDs.insert(pin.repository.id).inserted {
                seenRepos.append(pin.repository)
            }
            let actorMaps = await throttledMap(seenRepos, concurrency: Self.maxConcurrency) { repository in
                await self.actorLogins(in: repository)
            }
            for (repository, map) in zip(seenRepos, actorMaps) {
                actorLoginsByRepo[repository.id] = map
            }
        }

        var pinSnapshots: [PinSnapshot] = []
        for (pin, result) in zip(pins, pinResults) {
            switch result {
            case let .success(runs):
                let actors = actorLoginsByRepo[pin.repository.id] ?? [:]
                let stamped = runs.map { run in
                    run.withActor(actors[run.id])
                }
                let latest = stamped.max { $0.sortDate < $1.sortDate }
                pinSnapshots.append(PinSnapshot(pin: pin, latestRun: latest))
            case let .failure(error):
                warnings.append("\(pin.repository.fullName) · \(pin.workflowName): \(error.localizedDescription)")
                pinSnapshots.append(PinSnapshot(pin: pin, runs: []))
            }
        }

        let merged = RunFilter.merge(filtered: filtered, pins: pinSnapshots)
        let active = RunGrouping.activeRuns(from: merged.filtered)
        let groups = RunGrouping.groups(
            from: merged.filtered,
            excluding: Set(active.map(\.id)),
            maxPerRepo: 3
        )
        let typicalDurations = await fetchTypicalDurations(
            repoResults: repoResults,
            pinResults: pinResults
        )

        return WorkflowSnapshot(
            pinned: merged.pinned,
            groups: groups,
            activeRuns: active,
            typicalDurations: typicalDurations,
            fetchedAt: .now,
            warnings: warnings
        )
    }

    private func fetchTypicalDurations(
        repoResults: [Result<[WorkflowRun], GhError>],
        pinResults: [Result<[WorkflowRun], GhError>]
    ) async -> [String: TimeInterval] {
        var runsByKey: [String: [WorkflowRun]] = [:]

        func collect(_ runs: [WorkflowRun]) {
            for run in runs {
                runsByKey[TypicalDuration.key(for: run), default: []].append(run)
            }
        }

        for result in repoResults {
            if case let .success(runs) = result {
                collect(runs)
            }
        }
        for result in pinResults {
            if case let .success(runs) = result {
                collect(runs)
            }
        }

        var seenIdentities = Set<String>()
        var identities: [(repository: Repository, workflowName: String)] = []
        for run in runsByKey.values.flatMap({ $0 }) where run.displayState == .running {
            let key = TypicalDuration.key(for: run)
            guard seenIdentities.insert(key).inserted else { continue }
            let name = run.workflowName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            identities.append((run.repository, name))
        }

        let historyResults = await throttledMap(identities, concurrency: Self.maxConcurrency) { identity in
            await self.fetchRuns(
                repository: identity.repository,
                user: nil,
                workflow: identity.workflowName,
                limit: TypicalDuration.sampleLimit,
                actorStamp: nil,
                status: "completed"
            )
        }
        for result in historyResults {
            if case let .success(runs) = result {
                collect(runs)
            }
        }

        var typicalDurations: [String: TimeInterval] = [:]
        for identity in identities {
            let key = TypicalDuration.key(repository: identity.repository, workflowName: identity.workflowName)
            if let median = TypicalDuration.median(of: runsByKey[key] ?? []) {
                typicalDurations[key] = median
            }
        }
        return typicalDurations
    }

    private func fetchRuns(
        repository: Repository,
        user: String?,
        workflow: String?,
        limit: Int,
        actorStamp: String?,
        status: String?
    ) async -> Result<[WorkflowRun], GhError> {
        var arguments = [
            "run", "list",
            "-R", repository.fullName,
            "--limit", String(max(limit, 1)),
            "--json", runJSONFields,
        ]
        if let user, !user.isEmpty {
            arguments.append(contentsOf: ["-u", user])
        }
        if let workflow, !workflow.isEmpty {
            arguments.append(contentsOf: ["-w", workflow])
        }
        if let status, !status.isEmpty {
            arguments.append(contentsOf: ["--status", status])
        }

        do {
            let output = try await process.run(arguments)
            if output.isEmpty { return .success([]) }
            let payload = try GitHubJSON.decoder().decode([GhRunDTO].self, from: Data(output.utf8))
            let runs = payload.compactMap { $0.workflowRun(repository: repository, actor: actorStamp) }
            return .success(runs)
        } catch let error as GhError {
            return .failure(error)
        } catch {
            return .failure(.decoding(error.localizedDescription))
        }
    }

    private func actorLogins(in repository: Repository) async -> [String: String] {
        do {
            let output = try await process.run([
                "api",
                "repos/\(repository.fullName)/actions/runs?per_page=100",
            ])
            if output.isEmpty || output == "{}" { return [:] }
            let payload = try GitHubJSON.decoder().decode(GhWorkflowRunsPageDTO.self, from: Data(output.utf8))
            var map: [String: String] = [:]
            for run in payload.workflowRuns {
                let login = run.actor?.login.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if !login.isEmpty {
                    map[String(run.id)] = login
                }
            }
            return map
        } catch {
            return [:]
        }
    }
}

func throttledMap<Input: Sendable, Output: Sendable>(
    _ inputs: [Input],
    concurrency: Int,
    operation: @Sendable @escaping (Input) async -> Output
) async -> [Output] {
    if inputs.isEmpty { return [] }

    var results = [Output?](repeating: nil, count: inputs.count)
    await withTaskGroup(of: (Int, Output).self) { group in
        var nextIndex = 0
        var inFlight = 0

        func enqueueMore() {
            while inFlight < max(concurrency, 1), nextIndex < inputs.count {
                let index = nextIndex
                let input = inputs[index]
                nextIndex += 1
                inFlight += 1
                group.addTask {
                    let value = await operation(input)
                    return (index, value)
                }
            }
        }

        enqueueMore()
        for await (index, value) in group {
            results[index] = value
            inFlight -= 1
            enqueueMore()
        }
    }
    return results.map { value in
        guard let value else {
            preconditionFailure("throttledMap missing a result")
        }
        return value
    }
}
