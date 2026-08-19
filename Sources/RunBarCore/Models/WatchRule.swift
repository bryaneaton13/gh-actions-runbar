import Foundation

public enum WorkflowEvent: String, Codable, CaseIterable, Sendable, Identifiable {
    case push
    case pullRequest = "pull_request"
    case workflowDispatch = "workflow_dispatch"
    case mergeGroup = "merge_group"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .push: return "My commits"
        case .pullRequest: return "Pull requests"
        case .workflowDispatch: return "Manual runs"
        case .mergeGroup: return "Merge queue"
        }
    }

    public var subtitle: String {
        switch self {
        case .push: return "push"
        case .pullRequest: return "pull_request"
        case .workflowDispatch: return "workflow_dispatch"
        case .mergeGroup: return "merge_group"
        }
    }

    public static func parse(_ raw: String?) -> WorkflowEvent? {
        guard let raw, !raw.isEmpty else { return nil }
        return WorkflowEvent(rawValue: raw)
    }
}

public struct WatchRule: Codable, Equatable, Sendable {
    public var onlyMyRuns: Bool
    public var events: Set<WorkflowEvent>

    public init(onlyMyRuns: Bool = true, events: Set<WorkflowEvent> = Set(WorkflowEvent.allCases)) {
        self.onlyMyRuns = onlyMyRuns
        self.events = events
    }

    public static let `default` = WatchRule()

    public var watchesAllEvents: Bool {
        events == Set(WorkflowEvent.allCases)
    }

    public var summaryLabel: String {
        if onlyMyRuns {
            return "my runs"
        }
        return "all runs"
    }
}
