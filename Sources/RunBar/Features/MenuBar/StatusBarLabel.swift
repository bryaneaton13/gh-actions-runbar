import RunBarCore
import SwiftUI

struct StatusBarLabel: View {
    let summary: ActivitySummary
    let isRefreshing: Bool

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: summary.symbolName)
                .foregroundStyle(summary.usesFailureTint ? RunBarTheme.failure : Color.primary)
                .overlay(alignment: .topTrailing) {
                    if summary.pinnedFailureCount > 0 {
                        Circle()
                            .fill(RunBarTheme.failure)
                            .frame(width: 6, height: 6)
                            .overlay(
                                Circle()
                                    .stroke(.background, lineWidth: 1)
                            )
                            .offset(x: 2, y: -2)
                    }
                }
            if let count = summary.statusBarCount {
                Text(count, format: .number)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(summary.statusBarCountUsesFailureTint ? RunBarTheme.failure : Color.primary)
            }
        }
        .opacity(isRefreshing && summary.activeRunCount == 0 && summary.pinnedFailureCount == 0 ? 0.7 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary.accessibilityLabel)
    }
}
