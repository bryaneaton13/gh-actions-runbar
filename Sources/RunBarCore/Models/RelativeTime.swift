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
        let interval = max(0, referenceDate.timeIntervalSince(start))
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 3600 ? [.hour, .minute] : [.minute, .second]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropLeading
        return formatter.string(from: interval) ?? "0s"
    }

    public static func timestamp(for run: WorkflowRun, referenceDate: Date = .now) -> String {
        switch run.displayState {
        case .queued:
            return "Queued \(description(of: run.activityDate, relativeTo: referenceDate))"
        case .running:
            return elapsed(from: run.startedAt ?? run.activityDate, to: referenceDate)
        case .succeeded, .failed, .cancelled, .neutral:
            return description(of: run.activityDate, relativeTo: referenceDate)
        }
    }
}
