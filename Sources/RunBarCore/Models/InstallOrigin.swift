import Foundation

public enum InstallOrigin: Equatable, Sendable {
    case homebrewFormula
    case other

    public static func from(bundlePath: String) -> InstallOrigin {
        if bundlePath.contains("/Cellar/runbar/") || bundlePath.contains("/opt/runbar/") {
            return .homebrewFormula
        }
        return .other
    }
}
