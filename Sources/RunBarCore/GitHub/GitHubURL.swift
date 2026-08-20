import Foundation

public enum GitHubURL {
    public static func isSafeToOpen(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else { return false }
        guard let host = url.host?.lowercased() else { return false }
        return host == "github.com" || host.hasSuffix(".github.com")
    }

    public static func parse(_ raw: String) -> URL? {
        guard let url = URL(string: raw), isSafeToOpen(url) else { return nil }
        return url
    }

    public static func actions(for repository: Repository) -> URL? {
        guard repository.isValid else { return nil }
        return parse("https://github.com/\(repository.fullName)/actions")
    }

    public static func releases(for repository: Repository) -> URL? {
        guard repository.isValid else { return nil }
        return parse("https://github.com/\(repository.fullName)/releases")
    }

    public static func workflow(for repository: Repository, path: String?) -> URL? {
        guard repository.isValid else { return nil }
        let file = workflowFileName(path)
        guard let file else { return nil }
        return parse("https://github.com/\(repository.fullName)/actions/workflows/\(file)")
    }

    public static func workflowFileName(_ path: String?) -> String? {
        let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        let file = trimmed.split(separator: "/").last.map(String.init) ?? trimmed
        guard !file.isEmpty, !file.hasPrefix("-"), !file.contains("\\") else { return nil }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "._-"))
        guard file.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return file
    }
}
