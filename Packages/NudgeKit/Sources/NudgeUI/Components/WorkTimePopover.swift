import NudgeCore
import SwiftUI

/// Hover breakdown for a row's timer: since-time, work/off-hours timeline, next tier.
struct WorkTimePopover: View {
    let row: PRRow
    let config: WorkHoursConfig
    let thresholds: TierThresholds
    var now: Date = .now

    private var since: Date? { row.pr.waitingSince }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(since.map { "Waiting since \(Format.weekdayTime($0))" } ?? "Request time unknown")
                    .font(Tokens.Typo.heading)
                Spacer(minLength: 16)
                if let since {
                    Text(DurationFormat.compact(now.timeIntervalSince(since)))
                        .font(Tokens.Typo.popoverTimer).monospacedDigit().tracking(-0.44)
                        .foregroundStyle(Tokens.Tier.text(row.tier))
                }
            }
            if let since {
                WorkTimeline(since: since, now: now, segments: WorkTime.segments(from: since, to: now, config: config))
                    .frame(height: 16)
                    .accessibilityLabel("Timeline: \(DurationFormat.compact(row.workSeconds ?? 0)) of work time")
                WorkTimelineLabels(since: since, now: now)
            }
            HStack(spacing: 16) {
                Label {
                    Text("Work time \(DurationFormat.compact(row.workSeconds ?? 0))")
                } icon: {
                    RoundedRectangle(cornerRadius: 3).fill(Tokens.Palette.secondary).frame(width: 12, height: 12)
                }
                Label {
                    Text("Off hours")
                } icon: {
                    Canvas { context, size in HatchStyle.draw(in: context, size: size, step: 6, width: 3) }
                        .frame(width: 12, height: 12)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .font(Tokens.Typo.settingsBody.weight(.semibold))
            .foregroundStyle(Tokens.Palette.secondary)
            Text(nextTierLine)
                .font(Tokens.Typo.heading)
                .foregroundStyle(nextTierColor)
        }
        .padding(16)
        .frame(width: 340)
        .foregroundStyle(Tokens.Palette.text)
    }

    private var nextTierLine: String {
        switch row.tier {
        case .fresh:
            if let left = row.workSecondsToNextTier { return "Turns amber after \(DurationFormat.compact(left)) more work time" }
            return "Turns amber after \(DurationFormat.compact(thresholds.amberWorkHours * 3600)) of work time"
        case .amber:
            if let left = row.workSecondsToNextTier { return "Turns red after \(DurationFormat.compact(left)) more work time" }
            return "Turns red after \(DurationFormat.compact(thresholds.redWorkHours * 3600)) of work time"
        case .red:
            return "Past \(DurationFormat.compact(thresholds.redWorkHours * 3600)) of work time"
        }
    }

    private var nextTierColor: Color {
        switch row.tier {
        case .fresh: Tokens.Tier.text(.amber)
        case .amber, .red: Tokens.Tier.text(.red)
        }
    }
}

/// Solid bars for working intervals over a hatched off-hours track.
struct WorkTimeline: View {
    let since: Date
    let now: Date
    let segments: [DateInterval]

    var body: some View {
        Canvas { context, size in
            let total = max(1, now.timeIntervalSince(since))
            let track = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 8)
            context.clip(to: track)
            HatchStyle.draw(in: context, size: size)
            for segment in segments {
                let x0 = size.width * CGFloat(segment.start.timeIntervalSince(since) / total)
                let x1 = size.width * CGFloat(segment.end.timeIntervalSince(since) / total)
                let rect = CGRect(x: x0, y: 0, width: max(2, x1 - x0), height: size.height)
                context.fill(Path(roundedRect: rect, cornerRadius: 2), with: .color(Tokens.Palette.secondary))
            }
        }
    }
}

struct WorkTimelineLabels: View {
    let since: Date
    let now: Date

    var body: some View {
        HStack {
            Text(Format.weekdayTime(since).components(separatedBy: " ").first ?? "")
            Spacer()
            ForEach(middleDays, id: \.self) { Text($0); Spacer() }
            Text(Format.weekdayTime(now))
        }
        .font(Tokens.Typo.caption)
        .foregroundStyle(Tokens.Palette.secondary)
    }

    private var middleDays: [String] {
        let calendar = Calendar.current
        var days: [String] = []
        var day = calendar.startOfDay(for: since)
        while let next = calendar.date(byAdding: .day, value: 1, to: day), next < now {
            days.append(next.formatted(.dateTime.weekday(.abbreviated)))
            day = next
        }
        return days.count > 4 ? [] : days
    }
}

enum HatchStyle {
    static func draw(in context: GraphicsContext, size: CGSize, step: CGFloat = 12, width: CGFloat = 5) {
        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color.primary.opacity(0.03)))
        var stripes = Path()
        var x: CGFloat = -size.height
        while x < size.width + size.height {
            stripes.move(to: CGPoint(x: x, y: size.height))
            stripes.addLine(to: CGPoint(x: x + size.height, y: 0))
            x += step
        }
        context.stroke(stripes, with: .color(Color.primary.opacity(0.1)), lineWidth: width)
    }
}
