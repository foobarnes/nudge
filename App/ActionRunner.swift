import AppKit
import NudgeCore

/// Runs review actions. Rendering (and all escaping of PR data) is NudgeCore's job; this file only executes
/// the rendered script or URL.
@MainActor
final class ActionRunner {
    private static let maxBackground = 4
    private static let debounce: TimeInterval = 2
    private static let automationSettings =
        URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!

    private let state: NudgeState
    private let alerts: NotificationService
    private let log = ActionLog()
    private var lastStart: [String: Date] = [:]
    private var running = 0
    private var queued: [BackgroundJob] = []

    init(state: NudgeState, alerts: NotificationService) {
        self.state = state
        self.alerts = alerts
    }

    /// `actionID == nil` runs every `runOnStart` action in order, or opens the PR when there are none.
    func startReview(_ row: PRRow, actionID: ReviewAction.ID?) {
        let key = "\(row.id)|\(actionID?.uuidString ?? "start")"
        if let last = lastStart[key], Date().timeIntervalSince(last) < Self.debounce { return }
        lastStart[key] = Date()

        let actions = state.settings.actions
        let selected = actionID.map { id in actions.filter { $0.id == id } } ?? actions.filter(\.runOnStart)
        if selected.isEmpty {
            if actionID == nil { NSWorkspace.shared.open(row.pr.url) }
            return
        }
        // Launch in list order without waiting; one failing launch doesn't stop the rest.
        for action in selected { run(action, pr: row.pr) }
    }

    func run(_ action: ReviewAction, pr: WaitingPR) {
        let rendered: RenderedAction
        do {
            rendered = try ActionRendering.render(action, pr: pr, allowedSchemes: state.settings.allowedURLSchemes)
        } catch {
            let message = (error as? ActionTemplateError)?.message ?? error.localizedDescription
            alerts.alert(title: "“\(action.name)” couldn't run", body: message)
            return
        }
        for _ in 0..<max(1, action.repeatCount) {
            switch rendered {
            case let .url(url):
                if !NSWorkspace.shared.open(url) {
                    alerts.alert(title: "“\(action.name)” couldn't open its link", body: url.absoluteString)
                }
            case let .shell(script):
                do {
                    let file = try writeScript(script)
                    switch action.kind {
                    case .background: enqueue(BackgroundJob(name: action.name, script: file, label: pr.repo + "#" + String(pr.number)))
                    case .terminal, .openURL: openInTerminal(file, actionName: action.name)
                    }
                } catch {
                    alerts.alert(title: "“\(action.name)” couldn't run", body: error.localizedDescription)
                }
            }
        }
    }

    // MARK: Script files

    /// A fresh 0700 directory per run holding a 0700 script. The script deletes itself on exit.
    private func writeScript(_ script: String) throws -> URL {
        let fm = FileManager.default
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("nudge-action-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        let file = dir.appendingPathComponent("action.zsh")
        guard fm.createFile(atPath: file.path, contents: Data(script.utf8), attributes: [.posixPermissions: 0o700])
        else { throw CocoaError(.fileWriteUnknown) }
        return file
    }

    // MARK: Terminal

    private func openInTerminal(_ script: URL, actionName: String) {
        switch state.settings.terminalApp {
        case .ghostty: openInGhostty(script, actionName: actionName)
        case .cmux: openInCmux(script, actionName: actionName)
        case .terminal: openInTerminalApp(script, actionName: actionName)
        }
    }

    private func openInGhostty(_ script: URL, actionName: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalApp.ghostty.bundleID) else {
            alerts.alert(title: "“\(actionName)” needs Ghostty",
                         body: "Ghostty isn't installed. Install it or pick Terminal in Settings › General.")
            return
        }
        // --wait-after-command keeps the window open so the command's output stays readable.
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", "-a", app.path, "--args", "--wait-after-command=true", "-e", "/bin/zsh", "-l", script.path]
        open.terminationHandler = { [alerts] process in
            let status = process.terminationStatus
            guard status != 0 else { return }
            Task { @MainActor in alerts.alert(title: "“\(actionName)” failed", body: "Ghostty didn't start (exit \(status)).") }
        }
        do { try open.run() } catch {
            alerts.alert(title: "“\(actionName)” failed", body: error.localizedDescription)
        }
    }

    /// A new cmux workspace named after the action, via cmux's bundled CLI. Launches cmux first if needed and
    /// retries while its socket comes up.
    private func openInCmux(_ script: URL, actionName: String) {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalApp.cmux.bundleID) else {
            alerts.alert(title: "“\(actionName)” needs cmux",
                         body: "cmux isn't installed. Install it or pick another terminal in Settings › General.")
            return
        }
        let cli = app.appendingPathComponent("Contents/Resources/bin/cmux")
        let quoted = "'" + script.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let arguments = ["workspace", "create", "--name", actionName, "--command", "/bin/zsh -l \(quoted)", "--focus", "true"]
        let alerts = self.alerts
        Task {
            let configuration = NSWorkspace.OpenConfiguration()
            _ = try? await NSWorkspace.shared.openApplication(at: app, configuration: configuration)   // launch + front
            var status: Int32 = -1
            for _ in 0..<10 {
                status = await Self.run(cli, arguments)
                if status == 0 { return }
                try? await Task.sleep(for: .milliseconds(500))
            }
            alerts.alert(title: "“\(actionName)” failed", body: "cmux didn't open a workspace (exit \(status)).")
        }
    }

    private nonisolated static func run(_ executable: URL, _ arguments: [String]) async -> Int32 {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(["CMUX_QUIET": "1"]) { $1 }
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { continuation.resume(returning: $0.terminationStatus) }
            do { try process.run() } catch { continuation.resume(returning: -1) }
        }
    }

    private func openInTerminalApp(_ script: URL, actionName: String) {
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: TerminalApp.terminal.bundleID) != nil else {
            alerts.alert(title: "“\(actionName)” needs Terminal", body: "Terminal isn't installed.")
            return
        }
        // The path is Nudge's own temp path (no PR data), and it still goes through `quoted form of`.
        let literal = script.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Terminal"
            activate
            do script "/bin/zsh -l " & quoted form of "\(literal)"
        end tell
        """
        let alerts = self.alerts
        // Off the main thread: the first run blocks on the Automation prompt.
        Task.detached {
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            guard let error else { return }
            let code = error[NSAppleScript.errorNumber] as? Int ?? 0
            let message = error[NSAppleScript.errorMessage] as? String ?? "AppleScript error \(code)"
            await MainActor.run {
                if code == -1743 {   // errAEEventNotPermitted: Automation denied
                    alerts.alert(title: "Nudge can't control Terminal",
                                 body: "Allow it in System Settings › Privacy & Security › Automation.",
                                 url: Self.automationSettings)
                } else {
                    alerts.alert(title: "“\(actionName)” failed", body: message)
                }
            }
        }
    }

    // MARK: Background

    private struct BackgroundJob {
        let name: String
        let script: URL
        let label: String
    }

    private func enqueue(_ job: BackgroundJob) {
        queued.append(job)
        drain()
    }

    private func drain() {
        while running < Self.maxBackground, !queued.isEmpty {
            launch(queued.removeFirst())
        }
    }

    private func launch(_ job: BackgroundJob) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", job.script.path]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = FileHandle.nullDevice
        let output = log.handle(header: "▶ \(job.name) · \(job.label)")
        process.standardOutput = output ?? FileHandle.nullDevice
        process.standardError = output ?? FileHandle.nullDevice
        let name = job.name
        let dir = job.script.deletingLastPathComponent()
        process.terminationHandler = { process in
            let status = process.terminationStatus
            try? output?.close()
            try? FileManager.default.removeItem(at: dir)
            Task { @MainActor [weak self] in self?.finished(name: name, status: status) }
        }
        do {
            try process.run()
            running += 1
        } catch {
            try? output?.close()
            alerts.alert(title: "“\(name)” failed", body: error.localizedDescription)
        }
    }

    private func finished(name: String, status: Int32) {
        running -= 1
        if status != 0 {
            alerts.alert(title: "“\(name)” failed", body: "Exited with status \(status). See ~/Library/Logs/Nudge/actions.log.")
        }
        drain()
    }
}

/// `~/Library/Logs/Nudge/actions.log`, 0600, rotated at 1 MB keeping one old file.
struct ActionLog {
    static let maxBytes = 1_000_000
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Nudge/actions.log")

    /// An append-only handle for one run, after writing a timestamped header line.
    func handle(header: String) -> FileHandle? {
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size >= Self.maxBytes {
            let old = url.appendingPathExtension("1")
            try? fm.removeItem(at: old)
            try? fm.moveItem(at: url, to: old)
        }
        let fd = open(url.path, O_WRONLY | O_APPEND | O_CREAT, 0o600)
        guard fd >= 0 else { return nil }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? handle.write(contentsOf: Data("\n[\(stamp)] \(header)\n".utf8))
        return handle
    }
}
