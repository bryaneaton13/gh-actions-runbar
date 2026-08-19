import Foundation

public enum UpdateCheckPolicy {
    public static let interval: TimeInterval = 24 * 60 * 60

    public static func shouldCheck(lastCheckAt: Date?, now: Date = .now, isSleeping: Bool) -> Bool {
        if isSleeping {
            return false
        }
        guard let lastCheckAt else { return true }
        return now.timeIntervalSince(lastCheckAt) >= interval
    }

    public static func isNewer(latest: AppVersion, than current: AppVersion) -> Bool {
        latest > current
    }
}
