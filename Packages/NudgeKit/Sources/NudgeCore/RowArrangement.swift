import Foundation

/// Display order for the request list: Settings' Sort by and Group by. `NudgeState.rows` stays oldest-first (the
/// pill's hero timer reads its first row); only the list is rearranged.
public enum RowArrangement {
    /// `rows` arrive oldest-first, and ties keep that order. Groups follow the sort: a group appears where its first
    /// row would.
    public static func arrange(_ rows: [PRRow], sort: RowSort, group: RowGrouping) -> [RowGroup] {
        let sorted = rows.enumerated().sorted { a, b in
            switch compare(a.element, b.element, sort) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: a.offset < b.offset
            }
        }.map(\.element)
        guard !sorted.isEmpty else { return [] }
        guard group != .none else { return [RowGroup(key: .all, rows: sorted)] }
        var order: [RowGroup.Key] = []
        var buckets: [RowGroup.Key: [PRRow]] = [:]
        for row in sorted {
            let key = key(row, group)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(row)
        }
        return order.map { RowGroup(key: $0, rows: buckets[$0] ?? []) }
    }

    private static func compare(_ a: PRRow, _ b: PRRow, _ sort: RowSort) -> ComparisonResult {
        switch sort {
        case .longestWaiting: .orderedSame
        case .newest: nilLast(a.pr.waitingSince, b.pr.waitingSince, descending: true)
        case .smallestDiff: nilLast(a.pr.diff?.lines, b.pr.diff?.lines)
        case .largestDiff: nilLast(a.pr.diff?.lines, b.pr.diff?.lines, descending: true)
        case .fewestFiles: nilLast(a.pr.diff?.files, b.pr.diff?.files)
        case .mostFiles: nilLast(a.pr.diff?.files, b.pr.diff?.files, descending: true)
        case .repository: nilLast(a.pr.repo.lowercased(), b.pr.repo.lowercased())
        }
    }

    /// Unknown values (no diff, no request time) go last in either direction.
    private static func nilLast<T: Comparable>(_ a: T?, _ b: T?, descending: Bool = false) -> ComparisonResult {
        switch (a, b) {
        case let (x?, y?) where x == y: .orderedSame
        case let (x?, y?): (x < y) != descending ? .orderedAscending : .orderedDescending
        case (.some, nil): .orderedAscending
        case (nil, .some): .orderedDescending
        case (nil, nil): .orderedSame
        }
    }

    private static func key(_ row: PRRow, _ group: RowGrouping) -> RowGroup.Key {
        switch group {
        case .none: .all
        case .repository: .repository(row.pr.repo)
        case .owner: .owner(row.pr.owner)
        case .urgency: .tier(row.tier)
        case .size: .size(row.pr.diff.map { DiffSize(lines: $0.lines) })
        case .author: .author(row.pr.author)
        }
    }
}

public enum RowSort: String, Codable, CaseIterable, Sendable {
    case longestWaiting, newest, smallestDiff, largestDiff, fewestFiles, mostFiles, repository
}

public enum RowGrouping: String, Codable, CaseIterable, Sendable {
    case none, repository, owner, urgency, size, author
}

/// Lines changed (added + removed), in the usual size-label buckets.
public enum DiffSize: Int, Comparable, CaseIterable, Sendable {
    case xs, s, m, l, xl

    public init(lines: Int) {
        self = switch lines {
        case ..<10: .xs
        case ..<50: .s
        case ..<250: .m
        case ..<1000: .l
        default: .xl
        }
    }

    public static func < (a: DiffSize, b: DiffSize) -> Bool { a.rawValue < b.rawValue }
}

public struct RowGroup: Identifiable, Hashable, Sendable {
    public enum Key: Hashable, Sendable {
        /// Group by: None. The list shows no header.
        case all
        case repository(String)
        case owner(String)
        case tier(Tier)
        /// nil: GitHub didn't report the diff.
        case size(DiffSize?)
        case author(String)
    }

    public var id: Key { key }
    public let key: Key
    public let rows: [PRRow]

    public init(key: Key, rows: [PRRow]) { self.key = key; self.rows = rows }
}
