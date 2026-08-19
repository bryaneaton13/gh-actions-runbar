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
    public var runs: [WorkflowRun]

    public init(pin: PinnedWorkflow, runs: [WorkflowRun] = []) {
        self.pin = pin
        self.runs = runs
    }

    public init(pin: PinnedWorkflow, latestRun: WorkflowRun?) {
        self.init(pin: pin, runs: latestRun.map { [$0] } ?? [])
    }

    public var id: String { pin.id }

    public var latestRun: WorkflowRun? {
        runs.max { $0.sortDate < $1.sortDate }
    }

    public var hasFailedLatestRun: Bool {
        latestRun?.displayState == .failed
    }
}
