import AppKit
import RunBarCore
import SwiftUI

struct RunRow: View {
    let run: WorkflowRun
    let referenceDate: Date
    var repositoryLabel: String? = nil
    var compact: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            NSWorkspace.shared.open(run.htmlURL)
        } label: {
            HStack(alignment: .center, spacing: 10) {
                statusIcon
                VStack(alignment: .leading, spacing: 3) {
                    Text(run.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(RelativeTime.timestamp(for: run, referenceDate: referenceDate))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(compact ? 8 : 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.35))
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Open in GitHub") {
                NSWorkspace.shared.open(run.htmlURL)
            }
            Button("Copy run URL") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(run.htmlURL.absoluteString, forType: .string)
            }
        }
        .help(run.displayTitle ?? run.name)
    }

    private var subtitle: String {
        var parts: [String] = []
        if let repositoryLabel {
            parts.append(repositoryLabel)
        }
        parts.append(run.branch)
        if let actor = run.actor, !actor.isEmpty {
            parts.append(actor)
        }
        if let event = run.event {
            parts.append(event.subtitle)
        }
        return parts.joined(separator: " · ")
    }

    private var statusIcon: some View {
        let color = RunBarTheme.color(for: run.displayState)
        return ZStack {
            Image(systemName: run.displayState.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
            if run.isActive {
                ActivePulseRing(color: color, isAnimated: !reduceMotion)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

private struct ActivePulseRing: View {
    let color: Color
    let isAnimated: Bool
    var period: TimeInterval = 1.2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !isAnimated)) { context in
            let progress = isAnimated ? pulseProgress(at: context.date) : 0
            Circle()
                .stroke(color.opacity(0.45), lineWidth: 1.5)
                .frame(width: 22, height: 22)
                .scaleEffect(1.0 + 0.28 * progress)
                .opacity(0.85 * (1.0 - progress))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func pulseProgress(at date: Date) -> CGFloat {
        let remainder = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period)
        return CGFloat(remainder / period)
    }
}

struct PinRow: View {
    let snapshot: PinSnapshot
    let referenceDate: Date

    var body: some View {
        if let run = snapshot.latestRun {
            RunRow(run: run, referenceDate: referenceDate, repositoryLabel: snapshot.pin.repository.fullName)
                .overlay {
                    if snapshot.hasFailedLatestRun {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(RunBarTheme.failure.opacity(0.55), lineWidth: 1)
                    }
                }
        } else {
            HStack(spacing: 10) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 3) {
                    Text(snapshot.pin.workflowName)
                        .font(.subheadline.weight(.medium))
                    Text("\(snapshot.pin.repository.fullName) · no recent runs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.quaternary.opacity(0.2))
            )
        }
    }
}
