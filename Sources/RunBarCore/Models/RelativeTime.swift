import Foundation

public enum RelativeTime {
    public static func description(of date: Date, relativeTo referenceDate: Date = .now) -> String {
        let seconds = Int(referenceDate.timeIntervalSince(date).rounded())
        if seconds < 0 {
            return "just now"
        }
        if seconds < 60 {
            return seconds <= 1 ? "just now" : "\(seconds) seconds ago"
        }

        let minutes = seconds / 60
        if minutes < 60 {
            return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
        }

        let hours = minutes / 60
        if hours < 24 {
            return hours == 1 ? "1 hour ago" : "\(hours) hours ago"
        }

        let days = hours / 24
        if days < 7 {
            return days == 1 ? "1 day ago" : "\(days) days ago"
        }
        if days < 14 {
            return "1 week ago"
        }
        if days < 30 {
            let weeks = days / 7
            return weeks == 1 ? "1 week ago" : "\(weeks) weeks ago"
        }

        let months = days / 30
        if months < 12 {
            return months == 1 ? "1 month ago" : "\(months) months ago"
        }

        let years = months / 12
        return years <= 1 ? "1 year ago" : "\(years) years ago"
    }

    public static func elapsed(from start: Date, to referenceDate: Date = .now) -> String {
        compact(referenceDate.timeIntervalSince(start))
    }

    public static func compact(_ interval: TimeInterval) -> String {
        let seconds = Int(max(0, interval).rounded())
        if seconds < 60 {
            return "\(seconds)s"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remain = minutes % 60
        if remain == 0 {
            return "\(hours)h"
        }
        return "\(hours)h \(remain)m"
    }

    public static func timestamp(
        for run: WorkflowRun,
        typicalDuration: TimeInterval? = nil,
        referenceDate: Date = .now
    ) -> String {
        switch run.displayState {
        case .queued:
            return "Queued \(description(of: run.activityDate, relativeTo: referenceDate))"
        case .running:
            let elapsedText = elapsed(from: run.startedAt ?? run.activityDate, to: referenceDate)
            if let typicalDuration, typicalDuration > 0 {
                return "\(elapsedText) · typically \(compact(typicalDuration))"
            }
            return elapsedText
        case .succeeded, .failed, .cancelled, .neutral:
            return description(of: run.activityDate, relativeTo: referenceDate)
        }
    }
}
