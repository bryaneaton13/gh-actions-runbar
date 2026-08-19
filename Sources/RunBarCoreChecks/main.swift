import Foundation
import RunBarCore

@main
enum RunBarCoreChecks {
    static func main() async {
        var failures = 0

        func check(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) {
            if !condition {
                fputs("FAIL \(file):\(line) \(message)\n", stderr)
                failures += 1
            }
        }

        func equal<T: Equatable>(_ actual: T, _ expected: T, _ message: String, file: String = #fileID, line: Int = #line) {
            check(actual == expected, "\(message) (got \(String(describing: actual)), expected \(String(describing: expected)))", file: file, line: line)
        }

        do {
            let repository = try Repository.parse("  Acme/App  ")
            equal(repository.fullName, "Acme/App", "parse owner/name")
            equal(repository.id, "acme/app", "canonical id")
        } catch {
            check(false, "parse should succeed: \(error)")
        }

        do {
            _ = try Repository.parse("nope")
            check(false, "invalid repo should throw")
        } catch {
            check(true, "invalid repo throws")
        }

        let now = Date(timeIntervalSince1970: 1_787_140_800)
        let repo = Repository(owner: "acme", name: "app")

        func run(
            id: String,
            status: WorkflowRunStatus = .completed,
            conclusion: WorkflowRunConclusion? = .success,
            actor: String? = "bryan",
            event: WorkflowEvent? = .push,
            name: String = "CI",
            repository: Repository = repo,
            createdAt: Date? = nil,
            startedAt: Date? = nil,
            updatedAt: Date = now
        ) -> WorkflowRun {
            WorkflowRun(
                id: id,
                repository: repository,
                workflowName: name,
                branch: "main",
                actor: actor,
                event: event,
                status: status,
                conclusion: conclusion,
                htmlURL: URL(string: "https://github.com/acme/app/actions/runs/\(id)")!,
                createdAt: createdAt,
                startedAt: startedAt ?? updatedAt.addingTimeInterval(-60),
                updatedAt: updatedAt
            )
        }

        let runningSummary = ActivitySummary(
            runs: [
                run(id: "1", status: .inProgress, conclusion: nil),
                run(id: "2", status: .queued, conclusion: nil),
            ],
            referenceDate: now
        )
        equal(runningSummary.activeRunCount, 2, "active count")
        equal(runningSummary.symbolName, "bolt.circle.fill", "running icon")
        equal(runningSummary.headline, "2 running", "running headline")

        let failureSummary = ActivitySummary(
            runs: [
                run(id: "1", status: .inProgress, conclusion: nil),
                run(id: "2", status: .completed, conclusion: .failure, updatedAt: now.addingTimeInterval(-5 * 60)),
            ],
            referenceDate: now
        )
        equal(failureSummary.symbolName, "exclamationmark.circle.fill", "failure icon")
        check(failureSummary.usesFailureTint, "failure tint")

        let idleSummary = ActivitySummary(runs: [], referenceDate: now)
        equal(idleSummary.symbolName, "bolt.circle", "idle icon")

        equal(RelativeTime.description(of: now.addingTimeInterval(-15 * 60), relativeTo: now), "15 minutes ago", "minutes")
        equal(RelativeTime.description(of: now.addingTimeInterval(-6 * 24 * 3600), relativeTo: now), "6 days ago", "six days is not a week")
        equal(RelativeTime.description(of: now.addingTimeInterval(-3 * 24 * 3600), relativeTo: now), "3 days ago", "three days")
        equal(RelativeTime.description(of: now.addingTimeInterval(-7 * 24 * 3600), relativeTo: now), "1 week ago", "seven days is a week")
        let staleUpdate = run(
            id: "stale",
            createdAt: now.addingTimeInterval(-15 * 60),
            startedAt: now.addingTimeInterval(-15 * 60),
            updatedAt: now.addingTimeInterval(-7 * 24 * 3600)
        )
        equal(RelativeTime.timestamp(for: staleUpdate, referenceDate: now), "15 minutes ago", "newest created/started date wins")

        let mine = run(id: "1", actor: "bryan", event: .push)
        let theirs = run(id: "2", actor: "sam", event: .push)
        let onlyMine = WatchRule(onlyMyRuns: true, events: Set(WorkflowEvent.allCases))
        check(RunFilter.matches(mine, rule: onlyMine, login: "bryan"), "keep my runs")
        check(!RunFilter.matches(theirs, rule: onlyMine, login: "bryan"), "drop other actors")

        let eventRule = WatchRule(onlyMyRuns: false, events: [.pullRequest, .workflowDispatch])
        check(RunFilter.matches(run(id: "1", event: .pullRequest), rule: eventRule, login: nil), "keep PR events")
        check(!RunFilter.matches(run(id: "2", event: .push), rule: eventRule, login: nil), "drop push when filtered")
        check(!RunFilter.matches(mine, rule: WatchRule(onlyMyRuns: false, events: []), login: nil), "empty events match nothing")

        let deploy = run(id: "100", actor: "sam", event: .workflowDispatch, name: "Deploy to prod")
        let ci = run(id: "101", actor: "bryan", event: .pullRequest, name: "CI")
        let merged = RunFilter.merge(
            filtered: [deploy, ci],
            pins: [PinSnapshot(pin: PinnedWorkflow(repository: repo, workflowName: "Deploy to prod"), latestRun: deploy)]
        )
        equal(merged.pinned.first?.latestRun?.id, "100", "pinned keeps deploy")
        equal(merged.filtered.map(\.id), ["101"], "filtered drops pinned id")

        let groups = RunGrouping.groups(
            from: [
                run(id: "1", updatedAt: now.addingTimeInterval(-120)),
                run(id: "2", updatedAt: now),
                run(id: "3", updatedAt: now.addingTimeInterval(-30)),
                run(id: "4", repository: Repository(owner: "acme", name: "api"), updatedAt: now.addingTimeInterval(-10)),
            ],
            maxPerRepo: 2
        )
        equal(groups.count, 2, "two repo groups")
        equal(groups.first?.repository.name, "app", "most recent repo first")
        equal(groups.first?.runs.map(\.id), ["2", "3"], "cap and sort runs")

        equal(
            PollingPolicy.intervalSeconds(popoverOpen: true, hasActiveRuns: false, isSleeping: false),
            PollingPolicy.activeInterval,
            "open poll interval"
        )
        equal(
            PollingPolicy.intervalSeconds(popoverOpen: false, hasActiveRuns: false, isSleeping: false),
            PollingPolicy.idleInterval,
            "idle poll interval"
        )
        check(
            PollingPolicy.intervalSeconds(popoverOpen: true, hasActiveRuns: true, isSleeping: true) == nil,
            "sleep pauses polling"
        )

        do {
            let payload = try GitHubJSON.decoder().decode([GhRunDTO].self, from: Data(fixtureJSON.utf8))
            equal(payload.count, 3, "fixture count")
            equal(payload[0].status, "in_progress", "first status")
            let running = payload[0].workflowRun(repository: repo, actor: "bryan")
            equal(running?.displayState, .running, "map in_progress")
            equal(payload[1].workflowRun(repository: repo, actor: nil)?.event, .workflowDispatch, "map dispatch")
            equal(payload[2].workflowRun(repository: repo, actor: "bryan")?.displayState, .failed, "map failure")
        } catch {
            check(false, "decode fixture: \(error)")
        }

        let process = FakeGhProcess()
        let client = GhClient(process: process)
        let snapshot = await client.fetchSnapshot(
            repositories: [repo],
            pins: [PinnedWorkflow(repository: repo, workflowName: "Deploy to prod")],
            rule: WatchRule(onlyMyRuns: true, events: [.pullRequest, .push, .workflowDispatch]),
            login: "bryan",
            runsPerRepo: 8,
            pinnedRunsLimit: 3
        )
        let commands = await process.commands
        equal(snapshot.pinned.first?.latestRun?.workflowName, "Deploy to prod", "pin latest")
        equal(snapshot.activeRuns.map(\.id), ["101"], "active CI")
        equal(snapshot.groups.flatMap(\.runs).map(\.id), ["99"], "completed leftover")
        check(commands.contains { $0.contains("-u") && $0.contains("bryan") }, "uses -u filter")
        check(commands.contains { $0.contains("-w") && $0.contains("Deploy to prod") }, "uses -w pin")

        do {
            let payload = try GitHubJSON.decoder().decode([GhAccessibleRepoDTO].self, from: Data(accessibleRepoJSON.utf8))
            equal(payload.count, 3, "accessible repo count")
            equal(payload[0].fullName, "acme/app", "full_name mapping")
            equal(payload[0].isPrivate, Optional(true), "private mapping")
            equal(payload[1].archived, Optional(true), "archived mapping")
            let summaries = payload.compactMap { dto -> GitHubRepositorySummary? in
                guard dto.archived != true else { return nil }
                return try? dto.summary()
            }
            equal(summaries.map(\.fullName), ["acme/app", "bryan/dotfiles"], "drop archived")
        } catch {
            check(false, "decode accessible repos: \(error)")
        }

        do {
            let orgs = try GitHubJSON.decoder().decode([GhOrgDTO].self, from: Data(#"[{"login":"acme"},{"login":"tango"}]"#.utf8))
            equal(orgs.map(\.login), ["acme", "tango"], "org logins")
        } catch {
            check(false, "decode orgs: \(error)")
        }

        let personal = GitHubRepositorySummary(
            repository: Repository(owner: "bryan", name: "dotfiles"),
            updatedAt: now
        )
        let orgRepo = GitHubRepositorySummary(
            repository: Repository(owner: "acme", name: "app"),
            description: "Actions dashboard",
            updatedAt: now.addingTimeInterval(-60)
        )
        let other = GitHubRepositorySummary(
            repository: Repository(owner: "sam", name: "tools"),
            updatedAt: now.addingTimeInterval(-120)
        )
        let owners = RepositoryCatalog.ownerChoices(
            viewerLogin: "bryan",
            organizations: ["tango", "acme"],
            repositories: [personal, orgRepo, other]
        )
        equal(owners, ["bryan", "acme", "tango", "sam"], "owner order")
        equal(
            RepositoryCatalog.filtered([personal, orgRepo, other], search: "", owner: "acme").map(\.fullName),
            ["acme/app"],
            "filter by org"
        )
        equal(
            RepositoryCatalog.filtered([personal, orgRepo, other], search: "dash", owner: nil).map(\.fullName),
            ["acme/app"],
            "filter by search"
        )
        let mergedCatalog = RepositoryCatalog.merging([personal], with: [orgRepo, personal])
        equal(mergedCatalog.map(\.fullName), ["bryan/dotfiles", "acme/app"], "merge unique newest first")

        let catalogProcess = FakeGhProcess()
        let catalogClient = GhClient(process: catalogProcess)
        let accessible = (try? await catalogClient.listAccessibleRepositories(limit: 400)) ?? []
        equal(accessible.map(\.fullName), ["acme/app", "bryan/dotfiles"], "accessible list drops archived")
        let catalogCommands = await catalogProcess.commands
        check(
            catalogCommands.contains { command in
                command.contains("api")
                    && command.contains { $0.contains("user/repos") && $0.contains("affiliation=owner,collaborator,organization_member") }
            },
            "lists affiliated repos"
        )
        let recent = (try? await catalogClient.listAccessibleRepositories(limit: RepositoryCatalog.recentLimit)) ?? []
        equal(recent.count, 2, "recent page keeps newest non-archived")
        let recentCommands = await catalogProcess.commands
        check(
            recentCommands.contains { command in
                command.contains { $0.contains("per_page=\(RepositoryCatalog.recentLimit)") }
            },
            "recent list uses a single small page"
        )
        let organizations = (try? await catalogClient.listOrganizations()) ?? []
        equal(organizations, ["acme", "tango"], "org list")

        do {
            let payload = try GitHubJSON.decoder().decode([GhSearchRepoDTO].self, from: Data(searchRepoJSON.utf8))
            equal(payload.map(\.fullName), ["acme/app"], "search json")
        } catch {
            check(false, "decode search repos: \(error)")
        }
        let searched = (try? await catalogClient.searchRepositories(query: "humming", owners: ["acme"])) ?? []
        equal(searched.map(\.fullName), ["acme/app"], "search results")
        let searchCommands = await catalogProcess.commands
        check(
            searchCommands.contains { command in
                command.starts(with: ["search", "repos"]) && command.contains("--owner") && command.contains("acme")
            },
            "search scopes to owner"
        )

        if failures == 0 {
            print("RunBarCoreChecks: all passed")
        } else {
            fputs("RunBarCoreChecks: \(failures) failed\n", stderr)
            exit(1)
        }
    }
}

private actor FakeGhProcess: GhRunning {
    private var storedCommands: [[String]] = []

    var commands: [[String]] { storedCommands }

    func run(_ arguments: [String]) async throws -> String {
        storedCommands.append(arguments)
        if arguments.starts(with: ["run", "list"]) {
            if let workflowIndex = arguments.firstIndex(of: "-w"),
               arguments.indices.contains(workflowIndex + 1),
               arguments[workflowIndex + 1] == "Deploy to prod"
            {
                return deployOnlyJSON
            }
            return fixtureJSON
        }
        if arguments.first == "api",
           arguments.contains(where: { $0.hasPrefix("user/repos") })
        {
            return accessibleRepoJSON
        }
        if arguments.first == "api",
           arguments.contains(where: { $0.hasPrefix("user/orgs") })
        {
            return #"[{"login":"acme"},{"login":"tango"}]"#
        }
        if arguments.starts(with: ["search", "repos"]) {
            return searchRepoJSON
        }
        throw GhError.failed(code: 1, message: "unexpected \(arguments.joined(separator: " "))")
    }
}

private let deployOnlyJSON = """
[
  {
    "databaseId": 100,
    "workflowName": "Deploy to prod",
    "displayTitle": "chore: release",
    "status": "completed",
    "conclusion": "success",
    "event": "workflow_dispatch",
    "headBranch": "main",
    "headSha": "def456",
    "name": "Deploy to prod",
    "startedAt": "2026-08-19T12:40:00Z",
    "updatedAt": "2026-08-19T12:55:00Z",
    "url": "https://github.com/acme/app/actions/runs/100"
  }
]
"""

private let searchRepoJSON = """
[
  {
    "fullName": "acme/app",
    "description": "Actions dashboard",
    "isPrivate": true,
    "isFork": false,
    "isArchived": false,
    "updatedAt": "2026-08-19T13:02:00Z"
  }
]
"""

private let accessibleRepoJSON = """
[
  {
    "full_name": "acme/app",
    "description": "Actions dashboard",
    "private": true,
    "fork": false,
    "archived": false,
    "updated_at": "2026-08-19T13:02:00Z"
  },
  {
    "full_name": "old/archive",
    "description": "retired",
    "private": false,
    "fork": false,
    "archived": true,
    "updated_at": "2024-01-01T00:00:00Z"
  },
  {
    "full_name": "bryan/dotfiles",
    "description": null,
    "private": true,
    "fork": false,
    "archived": false,
    "updated_at": "2026-08-18T12:00:00Z"
  }
]
"""

private let fixtureJSON = """
[
  {
    "databaseId": 101,
    "workflowName": "CI",
    "displayTitle": "feat: menu bar",
    "status": "in_progress",
    "conclusion": null,
    "event": "pull_request",
    "headBranch": "feat/runbar",
    "headSha": "abc123",
    "name": "CI",
    "startedAt": "2026-08-19T13:01:00Z",
    "updatedAt": "2026-08-19T13:02:00Z",
    "url": "https://github.com/acme/app/actions/runs/101"
  },
  {
    "databaseId": 100,
    "workflowName": "Deploy to prod",
    "displayTitle": "chore: release",
    "status": "completed",
    "conclusion": "success",
    "event": "workflow_dispatch",
    "headBranch": "main",
    "headSha": "def456",
    "name": "Deploy to prod",
    "startedAt": "2026-08-19T12:40:00Z",
    "updatedAt": "2026-08-19T12:55:00Z",
    "url": "https://github.com/acme/app/actions/runs/100"
  },
  {
    "databaseId": 99,
    "workflowName": "CI",
    "displayTitle": "fix: tests",
    "status": "completed",
    "conclusion": "failure",
    "event": "push",
    "headBranch": "main",
    "headSha": "ghi789",
    "name": "CI",
    "startedAt": "2026-08-19T12:10:00Z",
    "updatedAt": "2026-08-19T12:18:00Z",
    "url": "https://github.com/acme/app/actions/runs/99"
  }
]
"""
