import Foundation

public struct MergedRuns: Equatable, Sendable {
    public var pinned: [PinSnapshot]
    public var filtered: [WorkflowRun]

    public init(pinned: [PinSnapshot], filtered: [WorkflowRun]) {
        self.pinned = pinned
        self.filtered = filtered
    }

    public var pinnedRunIDs: Set<String> {
        Set(pinned.compactMap(\.latestRun?.id))
    }

    public var allRuns: [WorkflowRun] {
        pinned.compactMap(\.latestRun) + filtered
    }
}

public enum RunFilter {
    public static func matches(_ run: WorkflowRun, rule: WatchRule, login: String?) -> Bool {
        if !matchesActor(run, rule: rule, login: login) {
            return false
        }
        return matchesEvent(run, rule: rule)
    }

    public static func matchesActor(_ run: WorkflowRun, rule: WatchRule, login: String?) -> Bool {
        guard rule.onlyMyRuns else { return true }
        guard let login, !login.isEmpty else { return true }
        guard let actor = run.actor, !actor.isEmpty else { return true }
        return actor.caseInsensitiveCompare(login) == .orderedSame
    }

    public static func matchesEvent(_ run: WorkflowRun, rule: WatchRule) -> Bool {
        if rule.events.isEmpty {
            return false
        }
        if rule.watchesAllEvents {
            return true
        }
        guard let event = run.event else {
            return false
        }
        return rule.events.contains(event)
    }

    public static func merge(filtered: [WorkflowRun], pins: [PinSnapshot]) -> MergedRuns {
        var seen = Set<String>()
        let uniquePins: [PinSnapshot] = pins.map { snapshot in
            guard let run = snapshot.latestRun else { return snapshot }
            if seen.insert(run.id).inserted {
                return snapshot
            }
            return PinSnapshot(pin: snapshot.pin, latestRun: nil)
        }

        let pinnedIDs = Set(uniquePins.compactMap(\.latestRun?.id))
        let uniqueFiltered = filtered.filter { run in
            !pinnedIDs.contains(run.id) && seen.insert(run.id).inserted
        }

        return MergedRuns(pinned: uniquePins, filtered: uniqueFiltered)
    }
}

public enum RunGrouping {
    public static func groups(
        from runs: [WorkflowRun],
        excluding excludedIDs: Set<String> = [],
        maxPerRepo: Int = 3
    ) -> [RepositoryRunGroup] {
        let remaining = runs.filter { !excludedIDs.contains($0.id) }
        let grouped = Dictionary(grouping: remaining, by: \.repository)
        return grouped.keys.sorted().compactMap { repository -> RepositoryRunGroup? in
            let sorted = (grouped[repository] ?? []).sorted { $0.sortDate > $1.sortDate }
            let trimmed = Array(sorted.prefix(maxPerRepo))
            guard !trimmed.isEmpty else { return nil }
            return RepositoryRunGroup(repository: repository, runs: trimmed)
        }
        .sorted { lhs, rhs in
            (lhs.runs.first?.sortDate ?? .distantPast) > (rhs.runs.first?.sortDate ?? .distantPast)
        }
    }

    public static func activeRuns(
        from runs: [WorkflowRun],
        excluding excludedIDs: Set<String> = []
    ) -> [WorkflowRun] {
        runs
            .filter { $0.isActive && !excludedIDs.contains($0.id) }
            .sorted { $0.sortDate > $1.sortDate }
    }
}
