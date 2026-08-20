import Foundation

public enum TypicalDuration {
    public static let sampleLimit = 10

    public static func key(repository: Repository, workflowName: String) -> String {
        let name = workflowName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return "\(repository.id)::\(name)"
    }

    public static func key(for run: WorkflowRun) -> String {
        key(repository: run.repository, workflowName: run.workflowName)
    }

    public static func duration(of run: WorkflowRun) -> TimeInterval? {
        guard run.status == .completed, countsTowardTypical(run.conclusion) else {
            return nil
        }
        guard let start = run.startedAt ?? run.createdAt else {
            return nil
        }
        let interval = run.updatedAt.timeIntervalSince(start)
        guard interval > 0 else {
            return nil
        }
        return interval
    }

    /// Newest completed runs first. Uses up to `sampleLimit` durations that count toward typical.
    public static func median(of runs: [WorkflowRun]) -> TimeInterval? {
        var seen = Set<String>()
        let unique = runs.filter { seen.insert($0.id).inserted }
        let durations = unique
            .sorted { $0.sortDate > $1.sortDate }
            .compactMap(duration(of:))
            .prefix(sampleLimit)
        return median(Array(durations))
    }

    public static func median(_ intervals: [TimeInterval]) -> TimeInterval? {
        guard !intervals.isEmpty else {
            return nil
        }
        let sorted = intervals.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func countsTowardTypical(_ conclusion: WorkflowRunConclusion?) -> Bool {
        switch conclusion {
        case .success, .failure, .timedOut:
            return true
        case .cancelled, .neutral, .skipped, .actionRequired, .startupFailure, .none:
            return false
        }
    }
}
