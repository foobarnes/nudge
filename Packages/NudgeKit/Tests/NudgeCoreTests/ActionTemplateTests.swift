import Foundation
@testable import NudgeCore
import Testing

@Suite struct ActionTemplateTests {
    func shell(_ template: String, title: String = "Fix token refresh") throws -> String {
        let action = ReviewAction(name: "t", symbol: "x", kind: .terminal, template: template)
        guard case let .shell(script) = try ActionRendering.render(action, pr: makePR(title: title), allowedSchemes: [])
        else { throw ActionTemplateError("not a shell action") }
        return script
    }

    func run(_ script: String) throws -> (stdout: String, scriptPath: String) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nudge-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let file = dir.appendingPathComponent("action.zsh")
        try script.write(to: file, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [file.path]
        process.currentDirectoryURL = dir
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (String(decoding: data, as: UTF8.self), file.path)
    }

    @Test func injectionIsInert() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nudge-marker-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let marker = dir.appendingPathComponent("pwned").path
        let title = "it's \"auth\" $(touch \(marker)) `touch \(marker)` ; touch \(marker); * ${(e)$(touch \(marker))}\nline two é"
        let script = try shell(#"printf '%s' "{title}"; printf '%s' {title}; printf '%s' "$(printf '%s' {title})""#,
                               title: title)
        let result = try run(script)
        #expect(result.stdout == title + title + title)
        #expect(!FileManager.default.fileExists(atPath: marker))
        #expect(!FileManager.default.fileExists(atPath: result.scriptPath), "script deletes itself")
    }

    @Test func scriptShape() throws {
        let script = try shell("review-tool \"/review {url}\" && printf '%s\\n' \"{title}\"",
                               title: "Fix \"auth\" $(touch /tmp/x) `id`")
        let lines = script.split(separator: "\n").map(String.init)
        #expect(lines.first == "emulate -R zsh")
        #expect(lines.contains("trap 'rm -f \"$0\"' EXIT"))
        #expect(lines.contains("export NUDGE_PR_URL='https://github.com/acme/api/pull/4211'"))
        #expect(lines.contains("export NUDGE_PR_TITLE='Fix \"auth\" $(touch /tmp/x) `id`'"))
        #expect(lines.contains("export NUDGE_PR_NUMBER='4211'"))
        #expect(lines.last == "review-tool \"/review ${NUDGE_PR_URL}\" && printf '%s\\n' \"${NUDGE_PR_TITLE}\"")
    }

    @Test func survivesUserShellOptions() throws {
        let script = try shell("print -r -- {title}", title: "two words *")
        let result = try run("setopt sh_word_split glob_subst\n" + script)
        #expect(result.stdout == "two words *\n")
    }

    @Test func rejectsTokenInSingleQuotes() {
        #expect(throws: ActionTemplateError("Token {title} is inside single quotes and would not expand")) {
            try shell("echo '{title}'")
        }
        #expect(ActionRendering.problems(template: "echo '{title}' '{title}'", kind: .background, allowedSchemes: [])
            == ["Token {title} is inside single quotes and would not expand"])
        #expect(ActionRendering.problems(template: #"echo "it's {title}" $'{x}' "$(printf '%s' {url})""#,
                                         kind: .terminal, allowedSchemes: []).isEmpty)
        #expect(ActionRendering.problems(template: "echo $'a\\'{repo}'", kind: .terminal, allowedSchemes: [])
            == ["Token {repo} is inside single quotes and would not expand"])
    }

    // MARK: url

    func url(_ template: String, title: String = "Fix token refresh", allowed: [String] = []) throws -> URL {
        let action = ReviewAction(name: "u", symbol: "x", kind: .openURL, template: template)
        guard case let .url(url) = try ActionRendering.render(action, pr: makePR(title: title), allowedSchemes: allowed)
        else { throw ActionTemplateError("not a URL") }
        return url
    }

    @Test func urlEncodesQueryValues() throws {
        let rendered = try url("https://example.com/review?u={url}&t={title}", title: "a&b=c#d%e").absoluteString
        #expect(rendered.hasSuffix("&t=a%26b%3Dc%23d%25e"))
        let components = URLComponents(string: rendered)!
        #expect(components.queryItems?.count == 2)
        #expect(components.queryItems?.first?.value == "https://github.com/acme/api/pull/4211")
    }

    @Test func urlEncodesPathSegments() throws {
        let rendered = try url("https://example.com/{repo}/x/{title}", title: "a/b?c#d e").absoluteString
        #expect(rendered == "https://example.com/acme%2Fapi/x/a%2Fb%3Fc%23d%20e")
    }

    @Test func urlRejectsUnsafeTemplates() {
        for template in ["file:///{name}", "javascript:{title}", "{url}", "https://{owner}.example.com/",
                         "data:text/html,{title}", "http://example.com/{name}", "myapp://open?u={url}", "no scheme {url}"] {
            #expect(throws: ActionTemplateError.self, "\(template)") { try url(template) }
            #expect(!ActionRendering.problems(template: template, kind: .openURL, allowedSchemes: []).isEmpty)
        }
        #expect(throws: ActionTemplateError.self) { try url("file:///{name}", allowed: ["file"]) }
    }

    @Test func urlAllowsListedCustomScheme() throws {
        #expect(try url("myapp://open?u={url}", allowed: ["MyApp"]).scheme == "myapp")
        #expect(ActionRendering.problems(template: "https://example.com/{number}", kind: .openURL, allowedSchemes: []).isEmpty)
    }
}
