import Foundation

public enum GitHubJSON {
    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = parseISO8601(value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unrecognized date: \(value)"
            )
        }
        return decoder
    }

    public static func parseISO8601(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        if let date = basic.date(from: value) {
            return date
        }
        // GitHub/CLI occasionally omit the timezone; treat that as UTC.
        let naive = ISO8601DateFormatter()
        naive.formatOptions = [.withYear, .withMonth, .withDay, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        naive.timeZone = TimeZone(secondsFromGMT: 0)
        return naive.date(from: value)
    }
}

public struct GhRunDTO: Decodable, Sendable, Equatable {
    public let databaseId: Int
    public let workflowName: String?
    public let displayTitle: String?
    public let status: String
    public let conclusion: String?
    public let event: String?
    public let headBranch: String?
    public let headSha: String?
    public let name: String?
    public let createdAt: Date?
    public let startedAt: Date?
    public let updatedAt: Date
    public let url: String

    public init(
        databaseId: Int,
        workflowName: String?,
        displayTitle: String?,
        status: String,
        conclusion: String?,
        event: String?,
        headBranch: String?,
        headSha: String?,
        name: String?,
        createdAt: Date? = nil,
        startedAt: Date?,
        updatedAt: Date,
        url: String
    ) {
        self.databaseId = databaseId
        self.workflowName = workflowName
        self.displayTitle = displayTitle
        self.status = status
        self.conclusion = conclusion
        self.event = event
        self.headBranch = headBranch
        self.headSha = headSha
        self.name = name
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.url = url
    }

    public func workflowRun(repository: Repository, actor: String?) -> WorkflowRun? {
        guard let htmlURL = GitHubURL.parse(url) else { return nil }
        let workflowName = resolvedWorkflowName
        return WorkflowRun(
            id: String(databaseId),
            repository: repository,
            workflowName: workflowName,
            displayTitle: displayTitle,
            branch: headBranch?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "unknown",
            actor: actor,
            event: WorkflowEvent.parse(event),
            status: WorkflowRunStatus.parse(status),
            conclusion: WorkflowRunConclusion.parse(conclusion),
            htmlURL: htmlURL,
            headSHA: headSha,
            createdAt: createdAt,
            startedAt: startedAt,
            updatedAt: updatedAt
        )
    }

    private var resolvedWorkflowName: String {
        let candidates = [workflowName, name, displayTitle]
        for candidate in candidates {
            if let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty {
                return trimmed
            }
        }
        return "Workflow"
    }
}

public struct GhRepoDTO: Decodable, Sendable, Equatable {
    public let nameWithOwner: String
    public let description: String?
    public let isPrivate: Bool?
    public let isFork: Bool?
    public let updatedAt: Date?

    public func repository() throws -> Repository {
        try Repository.parse(nameWithOwner)
    }

    public func summary() throws -> GitHubRepositorySummary {
        GitHubRepositorySummary(
            repository: try repository(),
            description: description,
            isPrivate: isPrivate ?? false,
            isFork: isFork ?? false,
            updatedAt: updatedAt
        )
    }
}

public struct GhAccessibleRepoDTO: Decodable, Sendable, Equatable {
    public let fullName: String
    public let description: String?
    public let isPrivate: Bool?
    public let isFork: Bool?
    public let archived: Bool?
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case description
        case isPrivate = "private"
        case isFork = "fork"
        case archived
        case updatedAt = "updated_at"
    }

    public func summary() throws -> GitHubRepositorySummary {
        GitHubRepositorySummary(
            repository: try Repository.parse(fullName),
            description: description,
            isPrivate: isPrivate ?? false,
            isFork: isFork ?? false,
            updatedAt: updatedAt
        )
    }
}

public struct GhOrgDTO: Decodable, Sendable, Equatable {
    public let login: String
}

public struct GhSearchRepoDTO: Decodable, Sendable, Equatable {
    public let fullName: String
    public let description: String?
    public let isPrivate: Bool?
    public let isFork: Bool?
    public let isArchived: Bool?
    public let updatedAt: Date?

    public func summary() throws -> GitHubRepositorySummary {
        GitHubRepositorySummary(
            repository: try Repository.parse(fullName),
            description: description,
            isPrivate: isPrivate ?? false,
            isFork: isFork ?? false,
            updatedAt: updatedAt
        )
    }
}

public struct GhWorkflowDTO: Decodable, Sendable, Equatable, Identifiable {
    public let name: String
    public let path: String?
    public let state: String?

    public var id: String { name }
}

public struct GitHubUser: Sendable, Equatable {
    public let login: String

    public init(login: String) {
        self.login = login
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
