import Foundation

public struct ActivitySummary: Sendable, Equatable {
    public let runningCount: Int
    public let queuedCount: Int
    public let recentFailureCount: Int
    public let recentlyCompletedCount: Int

    public init(
        runningCount: Int,
        queuedCount: Int,
        recentFailureCount: Int,
        recentlyCompletedCount: Int
    ) {
        self.runningCount = runningCount
        self.queuedCount = queuedCount
        self.recentFailureCount = recentFailureCount
        self.recentlyCompletedCount = recentlyCompletedCount
    }

    public init(runs: [WorkflowRun], referenceDate: Date = .now) {
        let recentWindow = referenceDate.addingTimeInterval(-30 * 60)
        runningCount = runs.filter { $0.status == .inProgress }.count
        queuedCount = runs.filter { $0.isActive && $0.status != .inProgress }.count
        recentFailureCount = runs.filter { $0.displayState == .failed && $0.activityDate > recentWindow }.count
        recentlyCompletedCount = runs.filter { $0.status == .completed && $0.activityDate > recentWindow }.count
    }

    public static let empty = ActivitySummary(
        runningCount: 0,
        queuedCount: 0,
        recentFailureCount: 0,
        recentlyCompletedCount: 0
    )

    public var activeRunCount: Int {
        runningCount + queuedCount
    }

    public var symbolName: String {
        if recentFailureCount > 0 {
            return "exclamationmark.circle.fill"
        }
        if activeRunCount > 0 {
            return "bolt.circle.fill"
        }
        if recentlyCompletedCount > 0 {
            return "checkmark.circle"
        }
        return "bolt.circle"
    }

    public var usesFailureTint: Bool {
        recentFailureCount > 0
    }

    public var headline: String {
        if recentFailureCount > 0 {
            return "\(recentFailureCount) recent failure\(recentFailureCount == 1 ? "" : "s")"
        }
        if activeRunCount > 0 {
            return "\(activeRunCount) running"
        }
        if recentlyCompletedCount > 0 {
            return "Recent activity is clear"
        }
        return "No matching workflow activity"
    }
}
