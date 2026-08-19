import Foundation

public struct ActivitySummary: Sendable, Equatable {
    public let runningCount: Int
    public let queuedCount: Int
    public let recentFailureCount: Int
    public let recentlyCompletedCount: Int
    public let pinnedFailureCount: Int

    public init(
        runningCount: Int,
        queuedCount: Int,
        recentFailureCount: Int,
        recentlyCompletedCount: Int,
        pinnedFailureCount: Int = 0
    ) {
        self.runningCount = runningCount
        self.queuedCount = queuedCount
        self.recentFailureCount = recentFailureCount
        self.recentlyCompletedCount = recentlyCompletedCount
        self.pinnedFailureCount = pinnedFailureCount
    }

    public init(runs: [WorkflowRun], pins: [PinSnapshot] = [], referenceDate: Date = .now) {
        let recentWindow = referenceDate.addingTimeInterval(-30 * 60)
        runningCount = runs.filter { $0.status == .inProgress }.count
        queuedCount = runs.filter { $0.isActive && $0.status != .inProgress }.count
        recentFailureCount = runs.filter { $0.displayState == .failed && $0.activityDate > recentWindow }.count
        recentlyCompletedCount = runs.filter { $0.status == .completed && $0.activityDate > recentWindow }.count
        pinnedFailureCount = pins.filter(\.hasFailedLatestRun).count
    }

    public static let empty = ActivitySummary(
        runningCount: 0,
        queuedCount: 0,
        recentFailureCount: 0,
        recentlyCompletedCount: 0,
        pinnedFailureCount: 0
    )

    public var activeRunCount: Int {
        runningCount + queuedCount
    }

    public var hasFailureAlert: Bool {
        pinnedFailureCount > 0 || recentFailureCount > 0
    }

    public var symbolName: String {
        if hasFailureAlert {
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
        hasFailureAlert
    }

    public var statusBarCount: Int? {
        if activeRunCount > 0 {
            return activeRunCount
        }
        if pinnedFailureCount > 0 {
            return pinnedFailureCount
        }
        return nil
    }

    public var statusBarCountUsesFailureTint: Bool {
        pinnedFailureCount > 0 && activeRunCount == 0
    }

    public var headline: String {
        if pinnedFailureCount > 0 {
            return "\(pinnedFailureCount) pinned failure\(pinnedFailureCount == 1 ? "" : "s")"
        }
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

    public var accessibilityLabel: String {
        var parts: [String] = [headline]
        if pinnedFailureCount > 0, activeRunCount > 0 {
            parts.append("\(activeRunCount) running")
        }
        return parts.joined(separator: ", ")
    }
}
