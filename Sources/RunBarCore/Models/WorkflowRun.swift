import Foundation

public enum WorkflowRunStatus: String, Codable, Sendable {
    case queued
    case inProgress = "in_progress"
    case completed
    case requested
    case waiting
    case pending

    public static func parse(_ raw: String) -> WorkflowRunStatus {
        WorkflowRunStatus(rawValue: raw) ?? .queued
    }

    public var isActive: Bool {
        switch self {
        case .queued, .inProgress, .requested, .waiting, .pending:
            return true
        case .completed:
            return false
        }
    }
}

public enum WorkflowRunConclusion: String, Codable, Sendable {
    case success
    case failure
    case cancelled
    case neutral
    case skipped
    case timedOut = "timed_out"
    case actionRequired = "action_required"
    case startupFailure = "startup_failure"

    public static func parse(_ raw: String?) -> WorkflowRunConclusion? {
        guard let raw, !raw.isEmpty else { return nil }
        if raw == "startup_failure" { return .startupFailure }
        return WorkflowRunConclusion(rawValue: raw)
    }

    public var isFailure: Bool {
        self == .failure || self == .timedOut || self == .startupFailure
    }
}

public enum WorkflowDisplayState: Sendable, Equatable {
    case queued
    case running
    case succeeded
    case failed
    case cancelled
    case neutral

    public var symbolName: String {
        switch self {
        case .queued: return "clock.fill"
        case .running: return "bolt.circle.fill"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "minus.circle.fill"
        case .neutral: return "circle.dashed"
        }
    }
}

public struct WorkflowRun: Hashable, Identifiable, Sendable, Equatable {
    public let id: String
    public let repository: Repository
    public let workflowName: String
    public let displayTitle: String?
    public let branch: String
    public let actor: String?
    public let event: WorkflowEvent?
    public let status: WorkflowRunStatus
    public let conclusion: WorkflowRunConclusion?
    public let htmlURL: URL
    public let headSHA: String?
    public let createdAt: Date?
    public let startedAt: Date?
    public let updatedAt: Date

    public init(
        id: String,
        repository: Repository,
        workflowName: String,
        displayTitle: String? = nil,
        branch: String,
        actor: String?,
        event: WorkflowEvent?,
        status: WorkflowRunStatus,
        conclusion: WorkflowRunConclusion?,
        htmlURL: URL,
        headSHA: String? = nil,
        createdAt: Date? = nil,
        startedAt: Date?,
        updatedAt: Date
    ) {
        self.id = id
        self.repository = repository
        self.workflowName = workflowName
        self.displayTitle = displayTitle
        self.branch = branch
        self.actor = actor
        self.event = event
        self.status = status
        self.conclusion = conclusion
        self.htmlURL = htmlURL
        self.headSHA = headSHA
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }

    public var displayState: WorkflowDisplayState {
        if status.isActive {
            return status == .inProgress ? .running : .queued
        }
        switch conclusion {
        case .success:
            return .succeeded
        case .failure, .timedOut, .startupFailure:
            return .failed
        case .cancelled:
            return .cancelled
        case .none, .neutral, .skipped, .actionRequired:
            return .neutral
        }
    }

    public var isActive: Bool {
        status.isActive
    }

    public var isRecentFailure: Bool {
        displayState == .failed && activityDate > Date.now.addingTimeInterval(-30 * 60)
    }

    public var activityDate: Date {
        [createdAt, startedAt, updatedAt].compactMap { $0 }.max() ?? updatedAt
    }

    public var sortDate: Date {
        activityDate
    }

    public var name: String {
        let trimmed = workflowName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return displayTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Workflow"
    }

    public func withActor(_ actor: String?) -> WorkflowRun {
        let trimmed = actor?.trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkflowRun(
            id: id,
            repository: repository,
            workflowName: workflowName,
            displayTitle: displayTitle,
            branch: branch,
            actor: trimmed?.isEmpty == false ? trimmed : self.actor,
            event: event,
            status: status,
            conclusion: conclusion,
            htmlURL: htmlURL,
            headSHA: headSHA,
            createdAt: createdAt,
            startedAt: startedAt,
            updatedAt: updatedAt
        )
    }
}

public struct RepositoryRunGroup: Identifiable, Hashable, Sendable, Equatable {
    public let repository: Repository
    public let runs: [WorkflowRun]

    public init(repository: Repository, runs: [WorkflowRun]) {
        self.repository = repository
        self.runs = runs
    }

    public var id: String { repository.id }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
