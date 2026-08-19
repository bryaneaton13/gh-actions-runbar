import Foundation

enum AppInfo {
    static let githubOwner = "bryaneaton13"
    static let githubRepo = "gh-actions-runbar"

    static let fallbackVersion = "0.1.0"

    static var marketingVersion: String {
        let bundleVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        if let bundleVersion, !bundleVersion.isEmpty, bundleVersion != "1.0" {
            return bundleVersion
        }
        return fallbackVersion
    }

    static var githubURL: URL {
        URL(string: "https://github.com/\(githubOwner)/\(githubRepo)")!
    }

    static var websiteURL: URL {
        URL(string: "https://\(githubOwner).github.io/\(githubRepo)/")!
    }

    static var privacyURL: URL {
        URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/blob/main/docs/privacy.md")!
    }

    static var licenseURL: URL {
        URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/blob/main/LICENSE")!
    }

    static var changelogURL: URL {
        URL(string: "https://github.com/\(githubOwner)/\(githubRepo)/blob/main/CHANGELOG.md")!
    }
}
