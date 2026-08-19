import Foundation

public enum PollingPolicy {
    public static let activeInterval: TimeInterval = 15
    public static let idleInterval: TimeInterval = 45
    public static let sleepCheckInterval: TimeInterval = 30

    /// Seconds to wait before the next refresh. `nil` means skip fetching (machine is asleep).
    public static func intervalSeconds(
        popoverOpen: Bool,
        hasActiveRuns: Bool,
        isSleeping: Bool
    ) -> TimeInterval? {
        if isSleeping {
            return nil
        }
        if popoverOpen || hasActiveRuns {
            return activeInterval
        }
        return idleInterval
    }
}
