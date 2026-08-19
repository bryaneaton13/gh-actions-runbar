import Foundation

public enum RepositoryParseError: LocalizedError, Sendable {
    case invalid

    public var errorDescription: String? {
        "Use owner/name, for example apple/swift."
    }
}

public struct Repository: Codable, Hashable, Identifiable, Sendable, Comparable {
    public var owner: String
    public var name: String

    public init(owner: String, name: String) {
        self.owner = owner
        self.name = name
    }

    public var id: String {
        "\(owner.lowercased())/\(name.lowercased())"
    }

    public var fullName: String {
        "\(owner)/\(name)"
    }

    public var isValid: Bool {
        Self.isValidComponent(owner) && Self.isValidComponent(name)
    }

    public static func isValidComponent(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("-"), !value.contains("/") else {
            return false
        }
        return value.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "."
                || scalar == "_"
                || scalar == "-"
        }
    }

    public static func parse(_ raw: String) throws -> Repository {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
            .map(String.init)
        guard parts.count == 2 else { throw RepositoryParseError.invalid }
        let owner = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let name = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidComponent(owner), isValidComponent(name) else {
            throw RepositoryParseError.invalid
        }
        return Repository(owner: owner, name: name)
    }

    public static func < (lhs: Repository, rhs: Repository) -> Bool {
        lhs.fullName.localizedCaseInsensitiveCompare(rhs.fullName) == .orderedAscending
    }
}
