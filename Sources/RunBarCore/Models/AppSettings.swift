import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var repositories: [Repository]
    public var watchRule: WatchRule
    public var pins: [PinnedWorkflow]
    public var pinsIncludeAllActors: Bool
    public var runsPerRepo: Int
    public var launchAtLogin: Bool

    public init(
        repositories: [Repository] = [],
        watchRule: WatchRule = .default,
        pins: [PinnedWorkflow] = [],
        pinsIncludeAllActors: Bool = true,
        runsPerRepo: Int = 8,
        launchAtLogin: Bool = false
    ) {
        self.repositories = repositories
        self.watchRule = watchRule
        self.pins = pins
        self.pinsIncludeAllActors = pinsIncludeAllActors
        self.runsPerRepo = runsPerRepo
        self.launchAtLogin = launchAtLogin
    }

    public static let `default` = AppSettings()

    enum CodingKeys: String, CodingKey {
        case repositories
        case watchRule
        case pins
        case pinsIncludeAllActors
        case runsPerRepo
        case launchAtLogin
    }

    public func sanitized() -> AppSettings {
        let validRepos = repositories.filter(\.isValid)
        var seen = Set<String>()
        let uniqueRepos = validRepos.filter { seen.insert($0.id).inserted }
        let validPins = pins.filter { pin in
            pin.repository.isValid && !pin.workflowName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return AppSettings(
            repositories: uniqueRepos,
            watchRule: watchRule,
            pins: validPins,
            pinsIncludeAllActors: pinsIncludeAllActors,
            runsPerRepo: max(runsPerRepo, 1),
            launchAtLogin: launchAtLogin
        )
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let looseRepos = try container.decodeIfPresent([LooseRepository].self, forKey: .repositories) ?? []
        let loosePins = try container.decodeIfPresent([LoosePin].self, forKey: .pins) ?? []
        repositories = looseRepos.compactMap(\.repository)
        watchRule = try container.decodeIfPresent(WatchRule.self, forKey: .watchRule) ?? .default
        pins = loosePins.compactMap(\.pin)
        pinsIncludeAllActors = try container.decodeIfPresent(Bool.self, forKey: .pinsIncludeAllActors) ?? true
        runsPerRepo = try container.decodeIfPresent(Int.self, forKey: .runsPerRepo) ?? 8
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self = sanitized()
    }
}

private struct LooseRepository: Decodable {
    let owner: String?
    let name: String?

    var repository: Repository? {
        guard let owner, let name else { return nil }
        return try? Repository.parse("\(owner)/\(name)")
    }
}

private struct LoosePin: Decodable {
    let repository: LooseRepository?
    let workflowName: String?

    var pin: PinnedWorkflow? {
        guard let repository = repository?.repository else { return nil }
        let name = workflowName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !name.isEmpty else { return nil }
        return PinnedWorkflow(repository: repository, workflowName: name)
    }
}
