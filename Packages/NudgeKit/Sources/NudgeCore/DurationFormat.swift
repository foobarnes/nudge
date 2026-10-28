import Foundation

public enum DurationFormat {
    /// "<1m", "45m", "4h 12m", "2d 3h".
    public static func compact(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let d = s / 86_400, h = (s % 86_400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return m < 1 ? "<1m" : "\(m)m"
    }

    /// "4:12:07", "27:03:11" — hours are not rolled into days.
    public static func clock(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        let h = s / 3600, m = (s % 3600) / 60, x = s % 60
        return "\(h):" + String(format: "%02d:%02d", m, x)
    }
}
