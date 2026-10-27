import Foundation

protocol TokenProviding: Sendable {
    /// The `gh` token for github.com, cached in memory; `refresh` re-reads it.
    func token(refresh: Bool) async throws -> String
}

actor GhTokenProvider: TokenProviding {
    private var cached: String?

    func token(refresh: Bool) async throws -> String {
        if !refresh, let cached { return cached }
        guard let gh = await Self.ghPath() else { throw SyncError.ghMissing }
        guard let result = try? await Self.run(gh, ["auth", "token", "--hostname", "github.com"]), result.status == 0
        else { throw SyncError.notLoggedIn }
        let token = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { throw SyncError.notLoggedIn }
        cached = token
        return token
    }

    static func ghPath() async -> String? {
        var environment: [String: String] = [:]
        #if DEBUG
        environment = ProcessInfo.processInfo.environment
        #endif
        return await resolveGhPath(environment: environment,
                                   isExecutable: { FileManager.default.isExecutableFile(atPath: $0) },
                                   shellLookup: {
                                       let lookup = try? await run("/bin/zsh", ["-lc", "command -v gh"])
                                       return lookup?.status == 0 ? lookup?.output : nil
                                   })
    }

    /// Homebrew locations first, then the login shell's PATH (Finder-launched apps lack it). `NUDGE_GH_PATH`
    /// (passed only in DEBUG builds) replaces the search entirely.
    static func resolveGhPath(environment: [String: String], isExecutable: (String) -> Bool,
                              shellLookup: () async -> String?) async -> String? {
        if let override = environment["NUDGE_GH_PATH"] { return isExecutable(override) ? override : nil }
        if let path = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].first(where: isExecutable) { return path }
        let found = await shellLookup()?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return found.hasPrefix("/") && isExecutable(found) ? found : nil
    }

    static func run(_ path: String, _ arguments: [String]) async throws -> (status: Int32, output: String) {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (finished.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
            do { try process.run() } catch { continuation.resume(throwing: error) }
        }
    }
}
