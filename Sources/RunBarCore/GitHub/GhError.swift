import Foundation

public enum GhError: LocalizedError, Sendable, Equatable {
    case notFound
    case unauthenticated(String)
    case failed(code: Int, message: String)
    case decoding(String)
    case timedOut
    case outputTooLarge

    public var errorDescription: String? {
        switch self {
        case .notFound:
            return "The GitHub CLI (gh) was not found. Install it with Homebrew: brew install gh"
        case let .unauthenticated(message):
            return message.isEmpty ? "Sign in with gh auth login." : message
        case let .failed(_, message):
            return message.isEmpty ? "gh failed." : message
        case let .decoding(message):
            return "Could not read gh output: \(message)"
        case .timedOut:
            return "gh did not finish in time."
        case .outputTooLarge:
            return "gh returned more output than RunBar will read."
        }
    }
}

public enum GhAuthState: Sendable, Equatable {
    case checking
    case missingCLI
    case loggedOut(String)
    case ready(login: String)

    public var login: String? {
        if case let .ready(login) = self { return login }
        return nil
    }

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

public protocol GhRunning: Sendable {
    func run(_ arguments: [String]) async throws -> String
}
