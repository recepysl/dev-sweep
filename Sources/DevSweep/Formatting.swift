import Foundation

enum Format {
    static func ago(_ date: Date, now: Date = Date()) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "just now" }
        if seconds < 3_600 { return "\(seconds / 60)m ago" }
        if seconds < 86_400 { return "\(seconds / 3_600)h ago" }
        return "\(seconds / 86_400)d ago"
    }

    static func duration(_ seconds: TimeInterval) -> String {
        seconds < 60 ? "\(Int(seconds.rounded())) s" : "\(Int(seconds / 60)) min \(Int(seconds) % 60) s"
    }

    static func idle(_ days: Int) -> String {
        switch days {
        case 0: return "used today"
        case 1: return "idle 1 day"
        default: return "idle \(days) days"
        }
    }
}
