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

        let rejectedRepos = ["-evil/app", "acme/--help", "acme/app/extra", "acme/has space", "acme/"]
        for raw in rejectedRepos {
            do {
                _ = try Repository.parse(raw)
                check(false, "should reject \(raw)")
            } catch {
                check(true, "rejects \(raw)")
            }
        }
        check(GitHubURL.isSafeToOpen(URL(string: "https://github.com/acme/app/actions/runs/1")!), "https github.com is safe")
        check(GitHubURL.isSafeToOpen(URL(string: "https://gist.github.com/acme")!), "github.com subdomain is safe")
        check(!GitHubURL.isSafeToOpen(URL(string: "file:///tmp/x")!), "file URL is unsafe")
        check(!GitHubURL.isSafeToOpen(URL(string: "https://evil.example/acme")!), "non-github host is unsafe")
        check(GitHubURL.parse("javascript:alert(1)") == nil, "javascript URL rejected")
        check(GitHubURL.actions(for: Repository(owner: "acme", name: "app"))?.absoluteString == "https://github.com/acme/app/actions", "actions URL")
        check(GitHubURL.actions(for: Repository(owner: "-evil", name: "app")) == nil, "invalid repo has no actions URL")

        do {
            let dirty = """
            {"repositories":[{"owner":"acme","name":"app"},{"owner":"--flag","name":"x"}],"pins":[{"repository":{"owner":"--flag","name":"x"},"workflowName":"CI"},{"repository":{"owner":"acme","name":"app"},"workflowName":"Deploy"}]}
            """
            let decoded = try JSONDecoder().decode(AppSettings.self, from: Data(dirty.utf8))
            equal(decoded.repositories.map(\.fullName), ["acme/app"], "drop invalid repos")
            equal(decoded.pins.map(\.workflowName), ["Deploy"], "drop pins with invalid repos")
            equal(decoded.pinsIncludeAllActors, true, "legacy settings include everyone's pin runs")
        } catch {
            check(false, "lossy settings decode: \(error)")
        }

        do {
            let mineOnlyPins = try JSONDecoder().decode(AppSettings.self, from: Data(#"{"pinsIncludeAllActors":false}"#.utf8))
            equal(mineOnlyPins.pinsIncludeAllActors, false, "decode Show everyone's runs off")
        } catch {
            check(false, "pinsIncludeAllActors decode: \(error)")
        }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let tempFile = tempDir.appendingPathComponent("config.json")
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            try Data("{}".utf8).write(to: tempFile)
            try ConfigPermissions.apply(directory: tempDir, file: tempFile)
            let dirMode = try FileManager.default.attributesOfItem(atPath: tempDir.path)[.posixPermissions] as? NSNumber
            let fileMode = try FileManager.default.attributesOfItem(atPath: tempFile.path)[.posixPermissions] as? NSNumber
            equal(dirMode?.intValue, ConfigPermissions.directory, "config dir 0700")
            equal(fileMode?.intValue, ConfigPermissions.file, "config file 0600")
        } catch {
            check(false, "config permissions: \(error)")
        }
        try? FileManager.default.removeItem(at: tempDir)

        do {
            _ = try await GhProcess(executablePath: "/bin/sleep", timeout: 0.3).run(["2"])
            check(false, "hung process should time out")
        } catch GhError.timedOut {
            check(true, "gh process times out")
        } catch {
            check(false, "timeout should be timedOut, got \(error)")
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

        let stalePinnedFailure = PinSnapshot(
            pin: PinnedWorkflow(repository: repo, workflowName: "Deploy to prod"),
            latestRun: run(
                id: "200",
                conclusion: .failure,
                name: "Deploy to prod",
                updatedAt: now.addingTimeInterval(-4 * 3600)
            )
        )
        let pinnedFailureSummary = ActivitySummary(
            runs: [stalePinnedFailure.latestRun!],
            pins: [stalePinnedFailure],
            referenceDate: now
        )
        equal(pinnedFailureSummary.pinnedFailureCount, 1, "stale pinned failure still counts")
        check(pinnedFailureSummary.usesFailureTint, "pinned failure tints menu bar")
        equal(pinnedFailureSummary.statusBarCount, Optional(1), "pinned failure badge")
        check(pinnedFailureSummary.statusBarCountUsesFailureTint, "badge uses failure tint")
        equal(pinnedFailureSummary.headline, "1 pinned failure", "pinned failure headline")
        equal(pinnedFailureSummary.symbolName, "exclamationmark.circle.fill", "pinned failure icon")

        let mixedPinnedSummary = ActivitySummary(
            runs: [
                run(id: "1", status: .inProgress, conclusion: nil),
                stalePinnedFailure.latestRun!,
            ],
            pins: [stalePinnedFailure],
            referenceDate: now
        )
        equal(mixedPinnedSummary.statusBarCount, Optional(1), "running count still shown")
        check(mixedPinnedSummary.usesFailureTint, "pinned failure still tints while running")
        check(!mixedPinnedSummary.statusBarCountUsesFailureTint, "running count stays primary")

        let recoveredPin = PinSnapshot(
            pin: PinnedWorkflow(repository: repo, workflowName: "Deploy to prod"),
            latestRun: run(id: "201", conclusion: .success, name: "Deploy to prod")
        )
        let recoveredSummary = ActivitySummary(runs: [recoveredPin.latestRun!], pins: [recoveredPin], referenceDate: now)
        equal(recoveredSummary.pinnedFailureCount, 0, "successful pin is not a failure")
        check(!recoveredSummary.usesFailureTint, "successful pin does not tint")
        equal(recoveredSummary.statusBarCount, Optional<Int>.none, "no badge when pin is healthy")

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
        let otherDeploy = run(id: "102", actor: "alex", event: .workflowDispatch, name: "Deploy to prod")
        let ci = run(id: "101", actor: "bryan", event: .pullRequest, name: "CI")
        let merged = RunFilter.merge(
            filtered: [deploy, otherDeploy, ci],
            pins: [PinSnapshot(pin: PinnedWorkflow(repository: repo, workflowName: "Deploy to prod"), runs: [deploy, otherDeploy])]
        )
        equal(merged.pinned.first?.runs.map(\.id), ["100", "102"], "pinned keeps every pin run")
        equal(merged.filtered.map(\.id), ["101"], "filtered drops all pinned ids")

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
            equal(payload[2].workflowRun(repository: repo, actor: "bryan")?.htmlURL.absoluteString, "https://github.com/acme/app/actions/runs/99", "keeps github https URL")
            let unsafe = GhRunDTO(
                databaseId: 1,
                workflowName: "CI",
                displayTitle: nil,
                status: "completed",
                conclusion: "success",
                event: "push",
                headBranch: "main",
                headSha: "abc",
                name: "CI",
                startedAt: now,
                updatedAt: now,
                url: "file:///tmp/evil"
            )
            check(unsafe.workflowRun(repository: repo, actor: nil) == nil, "drop non-https run URL")
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
            pinnedRunsLimit: 3,
            pinsIncludeAllActors: true
        )
        let commands = await process.commands
        equal(snapshot.pinned.first?.latestRun?.workflowName, "Deploy to prod", "pin latest")
        equal(snapshot.pinned.first?.runs.count, 2, "pin keeps everyone's recent runs")
        equal(snapshot.pinned.first?.latestRun?.actor, "sam", "pin hydrates actor from gh api")
        equal(snapshot.pinned.first?.runs.map(\.actor), ["sam", "bryan"], "pin rows show who triggered each run")
        equal(snapshot.activeRuns.map(\.id), ["101"], "active CI")
        equal(snapshot.groups.flatMap(\.runs).map(\.id), ["99"], "completed leftover")
        check(commands.contains { $0.contains("-u") && $0.contains("bryan") && !$0.contains("-w") }, "repo list uses -u")
        check(
            commands.contains { $0.contains("-w") && $0.contains("Deploy to prod") && !$0.contains("-u") },
            "pin skips -u when including everyone"
        )
        check(
            commands.contains { command in
                command.first == "api" && command.contains { $0.contains("repos/acme/app/actions/runs") }
            },
            "loads pin actors from gh api"
        )

        let mineOnlyProcess = FakeGhProcess()
        let mineOnlyClient = GhClient(process: mineOnlyProcess)
        let mineOnlySnapshot = await mineOnlyClient.fetchSnapshot(
            repositories: [repo],
            pins: [PinnedWorkflow(repository: repo, workflowName: "Deploy to prod")],
            rule: WatchRule(onlyMyRuns: true, events: [.pullRequest, .push, .workflowDispatch]),
            login: "bryan",
            runsPerRepo: 8,
            pinnedRunsLimit: 3,
            pinsIncludeAllActors: false
        )
        let mineOnlyCommands = await mineOnlyProcess.commands
        equal(mineOnlySnapshot.pinned.first?.runs.count, 1, "pin keeps latest when limited to my runs")
        check(
            mineOnlyCommands.contains { $0.contains("-w") && $0.contains("Deploy to prod") && $0.contains("-u") && $0.contains("bryan") },
            "pin uses -u when Show everyone's runs is off"
        )
        check(
            !mineOnlyCommands.contains { command in
                command.first == "api" && command.contains { $0.contains("/actions/runs") }
            },
            "skips actor hydration when pins use -u"
        )

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

        equal(AppVersion.parse("0.3.0"), AppVersion(major: 0, minor: 3, patch: 0), "parse version")
        equal(AppVersion.parse("v0.3.0"), AppVersion(major: 0, minor: 3, patch: 0), "parse v-prefix")
        check(AppVersion.parse("1.2") == nil, "reject two-part version")
        check(AppVersion.parse("1.2.3-beta") == nil, "reject prerelease tag")
        check(AppVersion.parse("v0.3.0")! > AppVersion.parse("0.2.0")!, "minor bump is newer")
        check(AppVersion.parse("1.0.0")! > AppVersion.parse("0.9.9")!, "major bump is newer")
        check(!(AppVersion.parse("0.2.0")! > AppVersion.parse("0.2.0")!), "same version is not newer")
        check(UpdateCheckPolicy.isNewer(latest: AppVersion(major: 0, minor: 3, patch: 0), than: AppVersion(major: 0, minor: 2, patch: 0)), "policy newer")
        check(!UpdateCheckPolicy.isNewer(latest: AppVersion(major: 0, minor: 2, patch: 0), than: AppVersion(major: 0, minor: 2, patch: 0)), "policy equal")
        check(!UpdateCheckPolicy.isNewer(latest: AppVersion(major: 0, minor: 2, patch: 0), than: AppVersion(major: 0, minor: 3, patch: 0)), "policy current ahead")

        let checkNow = Date(timeIntervalSince1970: 1_787_140_800)
        check(
            UpdateCheckPolicy.shouldCheck(lastCheckAt: nil, now: checkNow, isSleeping: false),
            "first check is due"
        )
        check(
            !UpdateCheckPolicy.shouldCheck(lastCheckAt: nil, now: checkNow, isSleeping: true),
            "sleep skips update check"
        )
        check(
            !UpdateCheckPolicy.shouldCheck(lastCheckAt: checkNow, now: checkNow, isSleeping: false),
            "just-checked is not due"
        )
        check(
            UpdateCheckPolicy.shouldCheck(
                lastCheckAt: checkNow.addingTimeInterval(-25 * 60 * 60),
                now: checkNow,
                isSleeping: false
            ),
            "24h interval elapsed"
        )

        equal(
            InstallOrigin.from(bundlePath: "/opt/homebrew/Cellar/runbar/0.2.0/RunBar.app"),
            .homebrewFormula,
            "Cellar is Homebrew"
        )
        equal(
            InstallOrigin.from(bundlePath: "/opt/runbar/0.2.0/RunBar.app"),
            .homebrewFormula,
            "opt prefix is Homebrew"
        )
        equal(
            InstallOrigin.from(bundlePath: "/Users/bryan/Applications/RunBar.app"),
            .other,
            "Applications is not Homebrew"
        )

        check(
            GitHubURL.releases(for: Repository(owner: "bryaneaton13", name: "gh-actions-runbar"))?.absoluteString
                == "https://github.com/bryaneaton13/gh-actions-runbar/releases",
            "releases URL"
        )
        check(GitHubURL.releases(for: Repository(owner: "-evil", name: "app")) == nil, "invalid repo has no releases URL")

        do {
            let release = try GhReleaseDTO(
                tagName: "v0.3.0",
                url: "https://github.com/bryaneaton13/gh-actions-runbar/releases/tag/v0.3.0"
            ).appRelease()
            equal(release.version, AppVersion(major: 0, minor: 3, patch: 0), "release version")
            equal(
                release.htmlURL.absoluteString,
                "https://github.com/bryaneaton13/gh-actions-runbar/releases/tag/v0.3.0",
                "release URL"
            )
        } catch {
            check(false, "valid release DTO: \(error)")
        }
        do {
            _ = try GhReleaseDTO(tagName: "v0.3.0", url: "file:///tmp/evil").appRelease()
            check(false, "unsafe release URL should throw")
        } catch GhError.decoding {
            check(true, "drop non-https release URL")
        } catch {
            check(false, "unsafe URL should be decoding, got \(error)")
        }
        do {
            _ = try GhReleaseDTO(tagName: "nightly", url: "https://github.com/acme/app/releases/tag/nightly").appRelease()
            check(false, "non-semver tag should throw")
        } catch GhError.decoding {
            check(true, "drop non-semver release tag")
        } catch {
            check(false, "non-semver should be decoding, got \(error)")
        }

        let cached = UpdateCheckRecord(
            lastCheckAt: checkNow,
            latestTag: "v0.3.0",
            latestURLString: "https://github.com/bryaneaton13/gh-actions-runbar/releases/tag/v0.3.0"
        )
        equal(cached.latestRelease?.version, AppVersion(major: 0, minor: 3, patch: 0), "cache restores release")
        let badCache = UpdateCheckRecord(lastCheckAt: checkNow, latestTag: "v0.3.0", latestURLString: "file:///tmp/x")
        check(badCache.latestRelease == nil, "cache drops unsafe URL")

        let releaseProcess = FakeGhProcess()
        let releaseClient = GhClient(process: releaseProcess)
        do {
            let appRepo = try Repository.parse("bryaneaton13/gh-actions-runbar")
            let fetchedRelease = try await releaseClient.latestRelease(in: appRepo)
            equal(fetchedRelease.version, AppVersion(major: 0, minor: 3, patch: 0), "client latest release")
            let releaseCommands = await releaseProcess.commands
            check(
                releaseCommands.contains { command in
                    command == ["release", "view", "--repo", "bryaneaton13/gh-actions-runbar", "--json", "tagName,url"]
                },
                "release view argv"
            )
            do {
                _ = try await releaseClient.latestRelease(in: Repository(owner: "-evil", name: "app"))
                check(false, "invalid repo should not call gh")
            } catch GhError.failed {
                check(true, "invalid repo fails before gh")
            } catch {
                check(false, "invalid repo should be failed, got \(error)")
            }
            let afterInvalid = await releaseProcess.commands
            equal(afterInvalid.count, releaseCommands.count, "invalid repo does not spawn gh")
        } catch {
            check(false, "latest release client: \(error)")
        }

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
           arguments.contains(where: { $0.contains("/actions/runs") })
        {
            return actionsRunsJSON
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
        if arguments.starts(with: ["release", "view"]) {
            return releaseJSON
        }
        throw GhError.failed(code: 1, message: "unexpected \(arguments.joined(separator: " "))")
    }
}

private let deployOnlyJSON = """
[
  {
    "databaseId": 102,
    "workflowName": "Deploy to prod",
    "displayTitle": "chore: release",
    "status": "completed",
    "conclusion": "success",
    "event": "workflow_dispatch",
    "headBranch": "main",
    "headSha": "aaa111",
    "name": "Deploy to prod",
    "startedAt": "2026-08-19T13:10:00Z",
    "updatedAt": "2026-08-19T13:20:00Z",
    "url": "https://github.com/acme/app/actions/runs/102"
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
  }
]
"""

private let actionsRunsJSON = """
{
  "workflow_runs": [
    {
      "id": 102,
      "actor": { "login": "sam" }
    },
    {
      "id": 100,
      "actor": { "login": "bryan" }
    }
  ]
}
"""

private let releaseJSON = """
{"tagName":"v0.3.0","url":"https://github.com/bryaneaton13/gh-actions-runbar/releases/tag/v0.3.0"}
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
