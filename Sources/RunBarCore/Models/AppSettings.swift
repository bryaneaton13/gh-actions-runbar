import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var repositories: [Repository]
    public var watchRule: WatchRule
    public var pins: [PinnedWorkflow]
    public var runsPerRepo: Int
    public var pinnedRunsLimit: Int
    public var launchAtLogin: Bool

    public init(
        repositories: [Repository] = [],
        watchRule: WatchRule = .default,
        pins: [PinnedWorkflow] = [],
        runsPerRepo: Int = 8,
        pinnedRunsLimit: Int = 3,
        launchAtLogin: Bool = false
    ) {
        self.repositories = repositories
        self.watchRule = watchRule
        self.pins = pins
        self.runsPerRepo = runsPerRepo
        self.pinnedRunsLimit = pinnedRunsLimit
        self.launchAtLogin = launchAtLogin
    }

    public static let `default` = AppSettings()
}
