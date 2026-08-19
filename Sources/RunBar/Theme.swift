import RunBarCore
import SwiftUI

enum RunBarTheme {
    static let success = Color(red: 0.247, green: 0.725, blue: 0.314)
    static let failure = Color(red: 0.973, green: 0.318, blue: 0.286)
    static let inProgress = Color(red: 0.824, green: 0.600, blue: 0.133)
    static let queued = Color(red: 0.545, green: 0.580, blue: 0.620)

    static func color(for state: WorkflowDisplayState) -> Color {
        switch state {
        case .queued:
            return queued
        case .running:
            return inProgress
        case .succeeded:
            return success
        case .failed:
            return failure
        case .cancelled, .neutral:
            return .secondary
        }
    }
}
