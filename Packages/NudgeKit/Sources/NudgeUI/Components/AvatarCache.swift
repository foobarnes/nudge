import AppKit

/// GitHub avatars by login (users and orgs alike), via `github.com/<login>.png`. Kept in memory for the session
/// and on disk for a day; a failed fetch is remembered for the session so the letter fallback doesn't refetch.
@MainActor
final class AvatarCache {
    static let shared = AvatarCache()

    private nonisolated static let maxAge: TimeInterval = 24 * 3600
    private nonisolated static let pixelSize = 128

    private var images: [String: NSImage?] = [:]
    private var inflight: [String: Task<NSImage?, Never>] = [:]
    private let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appending(path: Bundle.main.bundleIdentifier ?? "Nudge").appending(path: "avatars")

    func image(for login: String) async -> NSImage? {
        let key = login.lowercased()
        if let cached = images[key] { return cached }
        if let task = inflight[key] { return await task.value }
        let file = directory.appending(path: "\(key).png")
        let task = Task { await Self.load(key, file: file) }
        inflight[key] = task
        let image = await task.value
        inflight[key] = nil
        images[key] = image
        return image
    }

    private nonisolated static func load(_ login: String, file: URL) async -> NSImage? {
        let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let stale = modified.map { Date().timeIntervalSince($0) > maxAge } ?? true
        if !stale, let image = NSImage(contentsOf: file) { return image }
        if let data = await fetch(login), let image = NSImage(data: data) {
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: file, options: .atomic)
            return image
        }
        // Offline or GitHub failed: a stale copy beats the letter.
        return NSImage(contentsOf: file)
    }

    private nonisolated static func fetch(_ login: String) async -> Data? {
        guard let encoded = login.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://github.com/\(encoded).png?size=\(pixelSize)"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }
}
