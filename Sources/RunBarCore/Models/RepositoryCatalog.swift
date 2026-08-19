import Foundation

public enum RepositoryCatalog {
    public static let recentLimit = 50
    public static let ownerLimit = 50
    public static let searchLimit = 25
    public static let minimumSearchCharacters = 2

    public static func ownerChoices(
        viewerLogin: String?,
        organizations: [String],
        repositories: [GitHubRepositorySummary]
    ) -> [String] {
        var ordered: [String] = []
        var seen = Set<String>()

        func append(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if seen.insert(trimmed.lowercased()).inserted {
                ordered.append(trimmed)
            }
        }

        if let viewerLogin {
            append(viewerLogin)
        }
        for organization in organizations.sorted(by: {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }) {
            append(organization)
        }
        let remaining = Set(repositories.map(\.repository.owner))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        for owner in remaining {
            append(owner)
        }
        return ordered
    }

    public static func filtered(
        _ repositories: [GitHubRepositorySummary],
        search: String,
        owner: String?
    ) -> [GitHubRepositorySummary] {
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let trimmedOwner = owner?.trimmingCharacters(in: .whitespacesAndNewlines)

        return repositories.filter { repo in
            if let trimmedOwner, !trimmedOwner.isEmpty {
                guard repo.repository.owner.compare(trimmedOwner, options: .caseInsensitive) == .orderedSame else {
                    return false
                }
            }
            guard !trimmedSearch.isEmpty else { return true }
            return repo.fullName.lowercased().contains(trimmedSearch)
                || (repo.description ?? "").lowercased().contains(trimmedSearch)
        }
    }

    public static func merging(
        _ existing: [GitHubRepositorySummary],
        with incoming: [GitHubRepositorySummary]
    ) -> [GitHubRepositorySummary] {
        var byID: [String: GitHubRepositorySummary] = [:]
        byID.reserveCapacity(existing.count + incoming.count)
        for repository in existing {
            byID[repository.id] = repository
        }
        for repository in incoming {
            byID[repository.id] = repository
        }
        return byID.values.sorted { lhs, rhs in
            (lhs.updatedAt ?? .distantPast) > (rhs.updatedAt ?? .distantPast)
        }
    }
}
