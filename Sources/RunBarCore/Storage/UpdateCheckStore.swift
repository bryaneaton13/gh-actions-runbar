import Foundation

public struct UpdateCheckRecord: Codable, Equatable, Sendable {
    public var lastCheckAt: Date
    public var latestTag: String?
    public var latestURLString: String?

    public init(lastCheckAt: Date, latestTag: String? = nil, latestURLString: String? = nil) {
        self.lastCheckAt = lastCheckAt
        self.latestTag = latestTag
        self.latestURLString = latestURLString
    }

    public var latestRelease: AppRelease? {
        guard let latestTag,
              let latestURLString,
              let version = AppVersion.parse(latestTag),
              let htmlURL = GitHubURL.parse(latestURLString)
        else {
            return nil
        }
        return AppRelease(version: version, tagName: latestTag, htmlURL: htmlURL)
    }
}

public struct UpdateCheckStore: Sendable {
    public static let defaultsKey = "runbar.update"

    public init() {}

    public func load() -> UpdateCheckRecord? {
        guard let data = UserDefaults.standard.data(forKey: Self.defaultsKey) else { return nil }
        return try? JSONDecoder().decode(UpdateCheckRecord.self, from: data)
    }

    public func save(_ record: UpdateCheckRecord) {
        guard let data = try? JSONEncoder().encode(record) else { return }
        UserDefaults.standard.set(data, forKey: Self.defaultsKey)
    }
}
