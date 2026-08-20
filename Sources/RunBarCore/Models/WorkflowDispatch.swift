import Foundation

public enum WorkflowInputType: String, Equatable, Sendable {
    case string
    case boolean
    case choice
    case environment
    case number

    public static func parse(_ raw: String?) -> WorkflowInputType {
        switch raw?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "boolean", "bool":
            return .boolean
        case "choice":
            return .choice
        case "environment":
            return .environment
        case "number":
            return .number
        default:
            return .string
        }
    }
}

public struct WorkflowInput: Equatable, Identifiable, Sendable {
    public var name: String
    public var description: String?
    public var type: WorkflowInputType
    public var required: Bool
    public var defaultValue: String?
    public var options: [String]

    public init(
        name: String,
        description: String? = nil,
        type: WorkflowInputType = .string,
        required: Bool = false,
        defaultValue: String? = nil,
        options: [String] = []
    ) {
        self.name = name
        self.description = description
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
        self.options = options
    }

    public var id: String { name }

    public var label: String {
        let trimmed = description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? name : trimmed
    }

    public var resolvedDefault: String {
        if let defaultValue, !defaultValue.isEmpty {
            return defaultValue
        }
        switch type {
        case .boolean:
            return "false"
        case .choice, .environment:
            return options.first ?? ""
        case .string, .number:
            return ""
        }
    }
}

public struct WorkflowDispatchSpec: Equatable, Sendable {
    public var supportsDispatch: Bool
    public var inputs: [WorkflowInput]

    public init(supportsDispatch: Bool, inputs: [WorkflowInput] = []) {
        self.supportsDispatch = supportsDispatch
        self.inputs = inputs
    }

    public static let unsupported = WorkflowDispatchSpec(supportsDispatch: false)
    public static let empty = WorkflowDispatchSpec(supportsDispatch: true)

    public var needsEnvironments: Bool {
        inputs.contains { $0.type == .environment }
    }
}

public struct WorkflowDispatchContext: Equatable, Sendable {
    public var pin: PinnedWorkflow
    public var spec: WorkflowDispatchSpec
    public var defaultBranch: String
    public var branches: [String]
    public var environments: [String]
    public var workflowPath: String?

    public init(
        pin: PinnedWorkflow,
        spec: WorkflowDispatchSpec,
        defaultBranch: String,
        branches: [String] = [],
        environments: [String] = [],
        workflowPath: String? = nil
    ) {
        self.pin = pin
        self.spec = spec
        self.defaultBranch = defaultBranch
        self.branches = branches
        self.environments = environments
        self.workflowPath = workflowPath
    }

    public var githubURL: URL? {
        GitHubURL.workflow(for: pin.repository, path: workflowPath)
    }
}

public enum WorkflowDispatchValues {
    public static func defaults(from spec: WorkflowDispatchSpec) -> [String: String] {
        var values: [String: String] = [:]
        for input in spec.inputs {
            values[input.name] = input.resolvedDefault
        }
        return values
    }

    public static func merging(_ current: [String: String], with spec: WorkflowDispatchSpec) -> [String: String] {
        var values = defaults(from: spec)
        for input in spec.inputs {
            if let existing = current[input.name], !existing.isEmpty {
                values[input.name] = existing
            }
        }
        return values
    }

    public static func missingRequired(spec: WorkflowDispatchSpec, values: [String: String]) -> [WorkflowInput] {
        spec.inputs.filter { input in
            guard input.required, input.type != .boolean else { return false }
            let value = values[input.name]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return value.isEmpty
        }
    }

    public static func fields(spec: WorkflowDispatchSpec, values: [String: String]) -> [(String, String)] {
        spec.inputs.compactMap { input in
            let raw = values[input.name] ?? input.resolvedDefault
            let value: String
            switch input.type {
            case .boolean:
                value = Self.booleanString(raw)
            case .number, .string, .choice, .environment:
                value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if value.isEmpty, input.type != .boolean {
                return nil
            }
            return (input.name, value)
        }
    }

    public static func booleanString(_ raw: String) -> String {
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "true", "yes", "y", "1":
            return "true"
        default:
            return "false"
        }
    }

    public static func isTrue(_ raw: String?) -> Bool {
        booleanString(raw ?? "") == "true"
    }
}
