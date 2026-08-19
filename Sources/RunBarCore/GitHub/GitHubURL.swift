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
}
