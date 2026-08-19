import RunBarCore
import SwiftUI

struct StatusBarLabel: View {
    let summary: ActivitySummary
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: summary.symbolName)
                .foregroundStyle(summary.usesFailureTint ? RunBarTheme.failure : Color.primary)
            if summary.activeRunCount > 0 {
                Text(summary.activeRunCount, format: .number)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .opacity(isRefreshing && summary.activeRunCount == 0 ? 0.7 : 1)
    }
}
