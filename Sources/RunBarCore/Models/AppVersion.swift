import Foundation

public struct AppVersion: Comparable, Equatable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func parse(_ raw: String) -> AppVersion? {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.first == "v" || value.first == "V" {
            value.removeFirst()
        }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard parts.count == 3 else { return nil }
        guard let major = parseComponent(parts[0]),
              let minor = parseComponent(parts[1]),
              let patch = parseComponent(parts[2])
        else {
            return nil
        }
        return AppVersion(major: major, minor: minor, patch: patch)
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major { return lhs.major < rhs.major }
        if lhs.minor != rhs.minor { return lhs.minor < rhs.minor }
        return lhs.patch < rhs.patch
    }

    private static func parseComponent(_ raw: String) -> Int? {
        guard !raw.isEmpty, raw.allSatisfy(\.isNumber), let value = Int(raw) else {
            return nil
        }
        return value
    }
}

public struct AppRelease: Equatable, Sendable {
    public let version: AppVersion
    public let tagName: String
    public let htmlURL: URL

    public init(version: AppVersion, tagName: String, htmlURL: URL) {
        self.version = version
        self.tagName = tagName
        self.htmlURL = htmlURL
    }
}
