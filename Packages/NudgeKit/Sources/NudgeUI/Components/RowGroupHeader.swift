import NudgeCore
import SwiftUI

/// Section header above a group of rows when Settings' Group by isn't None.
struct RowGroupHeader: View {
    let group: RowGroup

    var body: some View {
        HStack(spacing: 7) {
            icon
            Text(verbatim: group.key.title)
                .font(Tokens.Typo.rowSubtitle.weight(.bold))
                .foregroundStyle(Tokens.Palette.secondary)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 8)
            Text(verbatim: "\(group.rows.count)")
                .font(Tokens.Typo.caption)
                .monospacedDigit()
                .foregroundStyle(Tokens.Palette.tertiary)
        }
        .padding(.horizontal, Tokens.Space.rowH)
        .padding(.top, 8).padding(.bottom, 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.key.title), \(group.rows.count)")
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var icon: some View {
        switch group.key {
        case let .repository(repo): Avatar(login: String(repo.split(separator: "/").first ?? ""), size: 16)
        case let .owner(login), let .author(login): Avatar(login: login, size: 16)
        case let .tier(tier): TierDot(tier: tier, isTeam: false, size: 9).frame(width: 16)
        case .size, .all: EmptyView()
        }
    }
}

extension RowGroup.Key {
    var title: String {
        switch self {
        case .all: ""
        case let .repository(name), let .owner(name), let .author(name): name
        case let .tier(tier): tier.title
        case let .size(size?): size.title
        case .size(nil): "Size unknown"
        }
    }
}

extension Tier {
    var title: String {
        switch self {
        case .fresh: "Fresh"
        case .amber: "Amber"
        case .red: "Red"
        }
    }
}

extension DiffSize {
    var title: String {
        switch self {
        case .xs: "XS · under 10 lines"
        case .s: "S · 10–49 lines"
        case .m: "M · 50–249 lines"
        case .l: "L · 250–999 lines"
        case .xl: "XL · 1,000+ lines"
        }
    }
}
