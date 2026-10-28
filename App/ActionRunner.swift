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
        let terminal = state.settings.terminalApp
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleID) else {
            alerts.alert(title: "“\(actionName)” needs \(terminal.title)",
                         body: "\(terminal.title) isn't installed. Install it or pick another terminal in Settings › General.")
            return
        }
        let quoted = Self.shellQuoted(script.path)
        // For terminals that close when their command exits: run the script, then stay in a shell so its output
        // stays readable.
        let keepOpen = "/bin/zsh -l \(quoted); exec /bin/zsh -l"
        switch terminal {
        case .ghostty:
            open(app, ["--wait-after-command=true", "-e", "/bin/zsh", "-l", script.path], terminal, actionName)
        case .wezterm:
            open(app, ["start", "--", "/bin/zsh", "-l", "-c", keepOpen], terminal, actionName)
        case .kitty:
            open(app, ["/bin/zsh", "-l", "-c", keepOpen], terminal, actionName)
        case .alacritty:
            open(app, ["-e", "/bin/zsh", "-l", "-c", keepOpen], terminal, actionName)
        case .cmux:
            openInCmux(app, command: "/bin/zsh -l \(quoted)", actionName: actionName)
        case .warp:
            openInWarp(command: "/bin/zsh -l \(quoted)", actionName: actionName)
        case .iterm:
            runAppleScript("""
            tell application "iTerm"
                activate
                tell current session of (create window with default profile) to write text "\(Self.appleScriptLiteral("/bin/zsh -l " + quoted))"
            end tell
            """, terminal, actionName)
        case .terminal:
            runAppleScript("""
            tell application "Terminal"
                activate
                do script "\(Self.appleScriptLiteral("/bin/zsh -l " + quoted))"
            end tell
            """, terminal, actionName)
        }
    }

    /// The script paths are Nudge's own temp paths (no PR data); they're still quoted for the shell.
    private static func shellQuoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptLiteral(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }

    /// A new instance of `app` with `arguments`, for terminals that take the command on their command line.
    private func open(_ app: URL, _ arguments: [String], _ terminal: TerminalApp, _ actionName: String) {
        let open = Process()
        open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        open.arguments = ["-n", "-a", app.path, "--args"] + arguments
        open.terminationHandler = { [alerts] process in
            let status = process.terminationStatus
            guard status != 0 else { return }
            Task { @MainActor in
                alerts.alert(title: "“\(actionName)” failed", body: "\(terminal.title) didn't start (exit \(status)).")
            }
        }
        do { try open.run() } catch {
            alerts.alert(title: "“\(actionName)” failed", body: error.localizedDescription)
        }
    }

    /// A new cmux workspace named after the action, via cmux's bundled CLI. Launches cmux first if needed and
    /// retries while its socket comes up.
    private func openInCmux(_ app: URL, command: String, actionName: String) {
        let cli = app.appendingPathComponent("Contents/Resources/bin/cmux")
        let arguments = ["workspace", "create", "--name", actionName, "--command", command, "--focus", "true"]
        let alerts = self.alerts
        Task {
            _ = try? await NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
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

    /// Warp has no command-line way to run a command; it runs one from a launch configuration opened by URL.
    private func openInWarp(command: String, actionName: String) {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".warp/launch_configurations")
        let file = dir.appendingPathComponent("Nudge.yaml")
        let yaml = """
        ---
        name: Nudge
        windows:
          - tabs:
              - title: "\(actionName.replacingOccurrences(of: "\"", with: "'"))"
                layout:
                  cwd: "\(NSHomeDirectory())"
                  commands:
                    - exec: "\(command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))"
        """
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try yaml.write(to: file, atomically: true, encoding: .utf8)
        } catch {
            alerts.alert(title: "“\(actionName)” failed", body: error.localizedDescription)
            return
        }
        var url = URLComponents()
        url.scheme = "warp"
        url.host = "launch"
        url.path = file.path
        guard let link = url.url, NSWorkspace.shared.open(link) else {
            alerts.alert(title: "“\(actionName)” failed", body: "Warp didn't open its launch configuration.")
            return
        }
    }

    private func runAppleScript(_ source: String, _ terminal: TerminalApp, _ actionName: String) {
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
                    alerts.alert(title: "Nudge can't control \(terminal.title)",
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
