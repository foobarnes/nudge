import Foundation

/// Renders user action templates. Shell kinds never put PR data into shell source: tokens become `${NUDGE_PR_*}`
/// references and the values travel as single-quote-escaped `export` lines. URL kinds encode per component.
enum ActionTemplate {
    static let tokenNames = ["url", "title", "repo", "owner", "name", "number", "branch"]

    struct Token {
        let name: String
        let range: Range<Int>
        let singleQuoted: Bool
    }

    static func values(_ pr: WaitingPR) -> [String: String] {
        ["url": pr.url.absoluteString, "title": pr.title, "repo": pr.repo, "owner": pr.owner, "name": pr.name,
         "number": String(pr.number), "branch": pr.headRef]
    }

    static func quotedTokenError(_ name: String) -> ActionTemplateError {
        ActionTemplateError("Token {\(name)} is inside single quotes and would not expand")
    }

    // MARK: Shell

    static func shellScript(_ template: String, _ pr: WaitingPR) throws -> String {
        let chars = Array(template)
        let tokens = scan(chars)
        if let quoted = tokens.first(where: \.singleQuoted) { throw quotedTokenError(quoted.name) }
        let body = substitute(chars, tokens) { "${NUDGE_PR_\($0.name.uppercased())}" }
        let values = values(pr)
        var script = "emulate -R zsh\ntrap 'rm -f \"$0\"' EXIT\n"
        for name in tokenNames {
            script += "export NUDGE_PR_\(name.uppercased())=\(singleQuoted(values[name] ?? ""))\n"
        }
        return script + body + (body.hasSuffix("\n") ? "" : "\n")
    }

    static func singleQuoted(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "\0", with: "").replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    // MARK: URL

    private static let blockedSchemes: Set<String> = ["file", "javascript", "data"]
    private static let pathAllowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
    private static let queryAllowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+#?"))

    static func url(_ template: String, _ pr: WaitingPR, allowedSchemes: [String]) throws -> URL {
        let chars = Array(template)
        let tokens = scan(chars)
        let firstToken = tokens.first?.range.lowerBound ?? chars.count
        guard let colon = chars.firstIndex(of: ":"), colon < firstToken else {
            throw ActionTemplateError(tokens.isEmpty ? "The URL needs a scheme, like https://"
                                                     : "Tokens can't be in the URL scheme")
        }
        let scheme = String(chars[..<colon]).lowercased()
        guard !scheme.isEmpty, scheme.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) })
        else { throw ActionTemplateError("The URL needs a scheme, like https://") }
        if blockedSchemes.contains(scheme) { throw ActionTemplateError("\(scheme): URLs are never allowed") }
        guard scheme == "https" || allowedSchemes.contains(where: { $0.lowercased() == scheme }) else {
            throw ActionTemplateError("The \(scheme): scheme isn't allowed; add it to the allowed URL schemes")
        }
        var authorityEnd = colon + 1
        if chars[(colon + 1)...].starts(with: "//") {
            authorityEnd = chars[(colon + 3)...].firstIndex(where: { "/?#".contains($0) }) ?? chars.count
            if firstToken < authorityEnd { throw ActionTemplateError("Tokens can't be in the URL host") }
        }
        let values = values(pr)
        let rendered = substitute(chars, tokens) { token in
            let before = chars[authorityEnd..<token.range.lowerBound]
            let allowed = before.contains("?") || before.contains("#") ? queryAllowed : pathAllowed
            return (values[token.name] ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        }
        guard let url = URL(string: rendered), url.scheme?.lowercased() == scheme,
              scheme != "https" || !(url.host() ?? "").isEmpty
        else { throw ActionTemplateError("The template doesn't render a valid URL") }
        return url
    }

    // MARK: Scanning

    private enum Context { case plain, paren, double, single, ansi }

    /// Finds `{token}` occurrences and whether each sits inside a zsh single-quoted string. Tracks `'…'`, `$'…'`,
    /// `"…"`, and `$(…)` (which resets quoting inside double quotes).
    static func scan(_ chars: [Character]) -> [Token] {
        var tokens: [Token] = []
        var stack: [Context] = [.plain]
        var i = 0
        while i < chars.count {
            let c = chars[i], next = i + 1 < chars.count ? chars[i + 1] : nil
            let top = stack.last ?? .plain
            if c == "{", let name = tokenNames.first(where: { matches(chars, at: i, "{\($0)}") }) {
                let length = name.count + 2
                tokens.append(Token(name: name, range: i..<(i + length), singleQuoted: top == .single || top == .ansi))
                i += length
                continue
            }
            switch top {
            case .single:
                if c == "'" { stack.removeLast() }
            case .ansi:
                if c == "\\" { i += 1 } else if c == "'" { stack.removeLast() }
            case .double:
                if c == "\\" { i += 1 } else if c == "\"" { stack.removeLast() }
                else if c == "$", next == "(" { stack.append(.paren); i += 1 }
            case .plain, .paren:
                if c == "\\" { i += 1 }
                else if c == "'" { stack.append(.single) }
                else if c == "\"" { stack.append(.double) }
                else if c == "$", next == "'" { stack.append(.ansi); i += 1 }
                else if c == "$", next == "(" { stack.append(.paren); i += 1 }
                else if c == "(", top == .paren { stack.append(.paren) }
                else if c == ")", top == .paren { stack.removeLast() }
            }
            i += 1
        }
        return tokens
    }

    private static func matches(_ chars: [Character], at i: Int, _ literal: String) -> Bool {
        chars[i...].starts(with: literal)
    }

    private static func substitute(_ chars: [Character], _ tokens: [Token], _ replacement: (Token) -> String) -> String {
        var out = "", cursor = 0
        for token in tokens {
            out += String(chars[cursor..<token.range.lowerBound]) + replacement(token)
            cursor = token.range.upperBound
        }
        return out + String(chars[cursor...])
    }

    static let samplePR = WaitingPR(
        prID: "PR_sample", repo: "acme/api", number: 4211, title: "Fix token refresh",
        url: URL(string: "https://github.com/acme/api/pull/4211")!, author: "alice", headRef: "fix-refresh",
        via: .direct, requestedBy: "alice", requestKey: "RRE_sample", requestedAt: nil, waitingSince: nil)
}

func _renderAction(_ action: ReviewAction, _ pr: WaitingPR, _ allowedSchemes: [String]) throws -> RenderedAction {
    switch action.kind {
    case .terminal, .background: .shell(script: try ActionTemplate.shellScript(action.template, pr))
    case .openURL: .url(try ActionTemplate.url(action.template, pr, allowedSchemes: allowedSchemes))
    }
}

func _actionProblems(_ template: String, _ kind: ReviewAction.Kind, _ allowedSchemes: [String]) -> [String] {
    switch kind {
    case .terminal, .background:
        var seen = Set<String>()
        return ActionTemplate.scan(Array(template)).filter { $0.singleQuoted && seen.insert($0.name).inserted }
            .map { ActionTemplate.quotedTokenError($0.name).message }
    case .openURL:
        do {
            _ = try ActionTemplate.url(template, ActionTemplate.samplePR, allowedSchemes: allowedSchemes)
            return []
        } catch let error as ActionTemplateError {
            return [error.message]
        } catch {
            return [error.localizedDescription]
        }
    }
}
