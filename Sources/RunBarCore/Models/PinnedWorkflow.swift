import Foundation

public struct PinnedWorkflow: Codable, Hashable, Identifiable, Sendable {
    public var repository: Repository
    public var workflowName: String

    public init(repository: Repository, workflowName: String) {
        self.repository = repository
        self.workflowName = workflowName
    }

    public var id: String {
        "\(repository.id)::\(workflowName.lowercased())"
    }
}

public struct PinSnapshot: Equatable, Sendable, Identifiable {
    public var pin: PinnedWorkflow
    public var latestRun: WorkflowRun?

    public init(pin: PinnedWorkflow, latestRun: WorkflowRun?) {
        self.pin = pin
        self.latestRun = latestRun
    }

    public var id: String { pin.id }

    public var hasFailedLatestRun: Bool {
        latestRun?.displayState == .failed
    }
}
