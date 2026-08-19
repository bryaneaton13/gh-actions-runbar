import Foundation

public struct WorkflowSnapshot: Sendable, Equatable {
    public var pinned: [PinSnapshot]
    public var groups: [RepositoryRunGroup]
    public var activeRuns: [WorkflowRun]
    public var fetchedAt: Date
    public var warnings: [String]

    public init(
        pinned: [PinSnapshot] = [],
        groups: [RepositoryRunGroup] = [],
        activeRuns: [WorkflowRun] = [],
        fetchedAt: Date = .now,
        warnings: [String] = []
    ) {
        self.pinned = pinned
        self.groups = groups
        self.activeRuns = activeRuns
        self.fetchedAt = fetchedAt
        self.warnings = warnings
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

    public func listWorkflows(in repository: Repository) async throws -> [GhWorkflowDTO] {
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

    public func fetchSnapshot(
        repositories: [Repository],
        pins: [PinnedWorkflow],
        rule: WatchRule,
        login: String?,
        runsPerRepo: Int,
        pinnedRunsLimit: Int,
        pinsIncludeAllActors: Bool = true
    ) async -> WorkflowSnapshot {
        let stampedActor = rule.onlyMyRuns ? login : nil
        let includeEveryoneOnPins = pinsIncludeAllActors || !rule.onlyMyRuns
        let pinUser = includeEveryoneOnPins ? nil : login
        let pinLimit = pinsIncludeAllActors ? pinnedRunsLimit : 1
        var warnings: [String] = []

        async let repoTask = throttledMap(repositories, concurrency: Self.maxConcurrency) { repository in
            await self.fetchRuns(
                repository: repository,
                user: rule.onlyMyRuns ? login : nil,
                workflow: nil,
                limit: runsPerRepo,
                actorStamp: stampedActor
            )
        }
        async let pinTask = throttledMap(pins, concurrency: Self.maxConcurrency) { pin in
            await self.fetchRuns(
                repository: pin.repository,
                user: pinUser,
                workflow: pin.workflowName,
                limit: pinLimit,
                actorStamp: pinUser
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
                let sorted = stamped.sorted { $0.sortDate > $1.sortDate }
                pinSnapshots.append(PinSnapshot(pin: pin, runs: Array(sorted.prefix(max(pinLimit, 1)))))
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

        return WorkflowSnapshot(
            pinned: merged.pinned,
            groups: groups,
            activeRuns: active,
            fetchedAt: .now,
            warnings: warnings
        )
    }

    private func fetchRuns(
        repository: Repository,
        user: String?,
        workflow: String?,
        limit: Int,
        actorStamp: String?
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
