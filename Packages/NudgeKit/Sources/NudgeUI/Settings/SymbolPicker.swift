import AppKit
import SwiftUI

/// Curated SF Symbols for review actions. macOS has no public API listing symbols, so search runs over
/// this list plus each entry's keywords; `SymbolCatalogTests` checks every name renders.
enum SymbolCatalog {
    struct Entry {
        let name: String
        let keywords: String
    }

    static let entries: [Entry] = [
        // Terminal and code
        .init(name: "terminal", keywords: "shell console command cli prompt"),
        .init(name: "terminal.fill", keywords: "shell console command cli prompt"),
        .init(name: "apple.terminal", keywords: "shell console command cli prompt"),
        .init(name: "chevron.left.forwardslash.chevron.right", keywords: "code html source editor"),
        .init(name: "curlybraces", keywords: "code json source editor"),
        .init(name: "curlybraces.square", keywords: "code json source editor"),
        .init(name: "chevron.left.slash.chevron.right", keywords: "code html source editor"),
        .init(name: "text.and.command.macwindow", keywords: "code app editor window"),
        .init(name: "macwindow", keywords: "app window editor"),
        .init(name: "macwindow.on.rectangle", keywords: "app window editor split"),
        .init(name: "rectangle.split.2x1", keywords: "split diff side by side compare"),
        .init(name: "square.split.2x1", keywords: "split diff compare"),
        .init(name: "keyboard", keywords: "type shortcut input"),
        .init(name: "command", keywords: "shortcut cmd key"),
        .init(name: "function", keywords: "fn code math"),
        .init(name: "number", keywords: "hash pr issue"),
        .init(name: "at", keywords: "mention email"),
        .init(name: "cpu", keywords: "processor chip compute build"),
        .init(name: "server.rack", keywords: "server deploy infra backend"),
        .init(name: "externaldrive", keywords: "disk storage database"),
        .init(name: "cylinder", keywords: "database db storage"),
        .init(name: "cylinder.split.1x2", keywords: "database db migration"),
        .init(name: "cube", keywords: "package module container"),
        .init(name: "cube.box", keywords: "package module container"),
        .init(name: "shippingbox", keywords: "package release ship npm container"),
        .init(name: "puzzlepiece", keywords: "plugin extension module"),
        .init(name: "puzzlepiece.extension", keywords: "plugin extension module"),
        .init(name: "gearshape", keywords: "settings config preferences"),
        .init(name: "gearshape.2", keywords: "settings config build pipeline"),
        .init(name: "slider.horizontal.3", keywords: "settings config tune"),
        .init(name: "switch.2", keywords: "toggle feature flag"),

        // Git and branches
        .init(name: "arrow.triangle.branch", keywords: "git branch fork merge"),
        .init(name: "arrow.triangle.merge", keywords: "git merge pull request"),
        .init(name: "arrow.triangle.pull", keywords: "git pull request pr"),
        .init(name: "arrow.triangle.swap", keywords: "git swap switch checkout"),
        .init(name: "arrow.branch", keywords: "git branch fork"),
        .init(name: "arrow.merge", keywords: "git merge"),
        .init(name: "arrow.trianglehead.branch", keywords: "git branch fork merge"),
        .init(name: "arrow.trianglehead.merge", keywords: "git merge pull request"),
        .init(name: "arrow.trianglehead.pull", keywords: "git pull request pr"),
        .init(name: "arrow.trianglehead.swap", keywords: "git swap switch checkout"),
        .init(name: "point.topleft.down.to.point.bottomright.curvepath", keywords: "git path flow"),
        .init(name: "point.3.connected.trianglepath.dotted", keywords: "git graph network nodes"),
        .init(name: "arrow.down.circle", keywords: "git pull fetch download"),
        .init(name: "arrow.up.circle", keywords: "git push upload"),
        .init(name: "arrow.up.arrow.down", keywords: "git sync push pull"),
        .init(name: "arrow.clockwise", keywords: "refresh reload retry rerun"),
        .init(name: "arrow.counterclockwise", keywords: "undo revert reset"),
        .init(name: "arrow.uturn.backward", keywords: "undo revert back"),
        .init(name: "arrow.uturn.forward", keywords: "redo forward"),
        .init(name: "arrow.triangle.2.circlepath", keywords: "sync refresh rebase loop"),
        .init(name: "arrow.2.squarepath", keywords: "sync repeat loop"),
        .init(name: "arrow.left.arrow.right", keywords: "compare diff swap"),
        .init(name: "arrow.right", keywords: "next go forward"),
        .init(name: "arrow.up.right", keywords: "open external link"),
        .init(name: "arrow.up.right.square", keywords: "open external link"),
        .init(name: "arrow.down.to.line", keywords: "download install"),
        .init(name: "arrow.up.to.line", keywords: "upload deploy publish"),
        .init(name: "square.and.arrow.up", keywords: "share export"),
        .init(name: "square.and.arrow.down", keywords: "save download import"),
        .init(name: "tray.and.arrow.down", keywords: "inbox download fetch"),
        .init(name: "tray.full", keywords: "inbox queue"),
        .init(name: "tag", keywords: "label release version"),
        .init(name: "flag", keywords: "mark report"),
        .init(name: "flag.checkered", keywords: "finish done release"),

        // Run and playback
        .init(name: "play", keywords: "run start launch go"),
        .init(name: "play.fill", keywords: "run start launch go"),
        .init(name: "play.circle", keywords: "run start launch go"),
        .init(name: "play.circle.fill", keywords: "run start launch go"),
        .init(name: "play.rectangle", keywords: "run video demo"),
        .init(name: "forward", keywords: "skip next fast"),
        .init(name: "forward.end", keywords: "skip next end"),
        .init(name: "stop", keywords: "halt end"),
        .init(name: "stop.circle", keywords: "halt end"),
        .init(name: "pause", keywords: "wait hold"),
        .init(name: "repeat", keywords: "loop again rerun"),
        .init(name: "bolt", keywords: "fast quick power action"),
        .init(name: "bolt.fill", keywords: "fast quick power action"),
        .init(name: "bolt.circle", keywords: "fast quick power action"),
        .init(name: "bolt.horizontal", keywords: "fast quick action"),
        .init(name: "hare", keywords: "fast quick speed"),
        .init(name: "tortoise", keywords: "slow speed"),
        .init(name: "gauge.with.dots.needle.67percent", keywords: "performance speed benchmark"),
        .init(name: "speedometer", keywords: "performance speed benchmark"),
        .init(name: "timer", keywords: "time stopwatch duration"),
        .init(name: "stopwatch", keywords: "time duration benchmark"),
        .init(name: "hourglass", keywords: "wait time pending"),
        .init(name: "clock", keywords: "time schedule history"),
        .init(name: "clock.arrow.circlepath", keywords: "history time recent"),
        .init(name: "calendar", keywords: "date schedule"),

        // Review and status
        .init(name: "eye", keywords: "review view look watch preview"),
        .init(name: "eye.fill", keywords: "review view look watch preview"),
        .init(name: "eye.circle", keywords: "review view look watch preview"),
        .init(name: "eyeglasses", keywords: "review read look"),
        .init(name: "magnifyingglass", keywords: "search find inspect review"),
        .init(name: "magnifyingglass.circle", keywords: "search find inspect review"),
        .init(name: "doc.text.magnifyingglass", keywords: "search review inspect file"),
        .init(name: "text.magnifyingglass", keywords: "search review find"),
        .init(name: "binoculars", keywords: "search explore look review"),
        .init(name: "checkmark", keywords: "done approve ok pass yes"),
        .init(name: "checkmark.circle", keywords: "done approve ok pass yes"),
        .init(name: "checkmark.circle.fill", keywords: "done approve ok pass yes"),
        .init(name: "checkmark.seal", keywords: "verified approve certified"),
        .init(name: "checkmark.seal.fill", keywords: "verified approve certified"),
        .init(name: "checkmark.shield", keywords: "secure verified safe"),
        .init(name: "checklist", keywords: "todo tasks review list"),
        .init(name: "checklist.checked", keywords: "todo tasks done list"),
        .init(name: "xmark", keywords: "close reject cancel fail no"),
        .init(name: "xmark.circle", keywords: "close reject cancel fail no"),
        .init(name: "xmark.octagon", keywords: "error stop reject fail"),
        .init(name: "exclamationmark.triangle", keywords: "warning alert caution"),
        .init(name: "exclamationmark.circle", keywords: "warning alert error"),
        .init(name: "questionmark.circle", keywords: "help unknown question"),
        .init(name: "info.circle", keywords: "info about details"),
        .init(name: "hand.thumbsup", keywords: "approve like lgtm good"),
        .init(name: "hand.thumbsdown", keywords: "reject dislike bad"),
        .init(name: "hand.raised", keywords: "stop block wait"),
        .init(name: "star", keywords: "favorite star rate"),
        .init(name: "star.fill", keywords: "favorite star rate"),
        .init(name: "bookmark", keywords: "save later mark"),
        .init(name: "pin", keywords: "pin keep save"),
        .init(name: "target", keywords: "goal focus aim"),
        .init(name: "scope", keywords: "focus aim target"),
        .init(name: "testtube.2", keywords: "test experiment lab"),
        .init(name: "flask", keywords: "test experiment lab"),
        .init(name: "chart.bar", keywords: "stats metrics graph"),
        .init(name: "chart.line.uptrend.xyaxis", keywords: "stats metrics graph trend"),
        .init(name: "list.bullet", keywords: "list items"),
        .init(name: "list.bullet.clipboard", keywords: "list tasks review checklist"),
        .init(name: "list.number", keywords: "list ordered steps"),
        .init(name: "text.badge.checkmark", keywords: "review approve text"),
        .init(name: "line.3.horizontal.decrease", keywords: "filter sort"),

        // Conversation
        .init(name: "bubble.left", keywords: "comment chat message review"),
        .init(name: "bubble.left.fill", keywords: "comment chat message review"),
        .init(name: "bubble.right", keywords: "comment chat message reply"),
        .init(name: "bubble.left.and.bubble.right", keywords: "comment chat conversation discuss review"),
        .init(name: "bubble.left.and.text.bubble.right", keywords: "comment chat conversation discuss"),
        .init(name: "text.bubble", keywords: "comment chat message review"),
        .init(name: "ellipsis.bubble", keywords: "comment typing chat pending"),
        .init(name: "quote.bubble", keywords: "comment quote chat"),
        .init(name: "exclamationmark.bubble", keywords: "comment alert important"),
        .init(name: "questionmark.bubble", keywords: "comment question ask"),
        .init(name: "message", keywords: "chat sms comment"),
        .init(name: "envelope", keywords: "email mail message"),
        .init(name: "paperplane", keywords: "send submit message"),
        .init(name: "paperplane.fill", keywords: "send submit message"),
        .init(name: "megaphone", keywords: "announce broadcast notify"),
        .init(name: "bell", keywords: "notify alert reminder"),
        .init(name: "bell.badge", keywords: "notify alert reminder unread"),
        .init(name: "person", keywords: "user author reviewer"),
        .init(name: "person.2", keywords: "users team reviewers pair"),
        .init(name: "person.crop.circle", keywords: "user author avatar profile"),
        .init(name: "person.crop.circle.badge.checkmark", keywords: "reviewer approve user"),
        .init(name: "person.3", keywords: "team group users"),

        // Docs and files
        .init(name: "doc", keywords: "file document page"),
        .init(name: "doc.text", keywords: "file document readme notes"),
        .init(name: "doc.on.doc", keywords: "copy duplicate files"),
        .init(name: "doc.on.clipboard", keywords: "copy paste clipboard"),
        .init(name: "doc.badge.plus", keywords: "new file add"),
        .init(name: "doc.richtext", keywords: "document rich text"),
        .init(name: "doc.plaintext", keywords: "file text log"),
        .init(name: "doc.zipper", keywords: "archive zip compress"),
        .init(name: "clipboard", keywords: "copy paste clipboard"),
        .init(name: "note.text", keywords: "notes memo"),
        .init(name: "book", keywords: "docs documentation read manual"),
        .init(name: "book.closed", keywords: "docs documentation manual"),
        .init(name: "books.vertical", keywords: "docs library documentation"),
        .init(name: "newspaper", keywords: "news changelog release notes"),
        .init(name: "text.document", keywords: "file document text"),
        .init(name: "folder", keywords: "directory files repo project"),
        .init(name: "folder.fill", keywords: "directory files repo project"),
        .init(name: "folder.badge.gearshape", keywords: "directory config settings"),
        .init(name: "folder.badge.plus", keywords: "new directory add"),
        .init(name: "archivebox", keywords: "archive storage box"),
        .init(name: "tray", keywords: "inbox queue"),
        .init(name: "paperclip", keywords: "attach attachment"),
        .init(name: "pencil", keywords: "edit write modify"),
        .init(name: "pencil.line", keywords: "edit write modify"),
        .init(name: "square.and.pencil", keywords: "edit compose write new"),
        .init(name: "highlighter", keywords: "highlight mark annotate"),
        .init(name: "trash", keywords: "delete remove"),
        .init(name: "photo", keywords: "image screenshot picture"),
        .init(name: "camera", keywords: "screenshot capture photo"),

        // Build and debug
        .init(name: "hammer", keywords: "build make compile"),
        .init(name: "hammer.fill", keywords: "build make compile"),
        .init(name: "hammer.circle", keywords: "build make compile"),
        .init(name: "wrench", keywords: "fix tool repair settings"),
        .init(name: "wrench.adjustable", keywords: "fix tool repair settings"),
        .init(name: "wrench.and.screwdriver", keywords: "tools fix build repair"),
        .init(name: "screwdriver", keywords: "tool fix repair"),
        .init(name: "ladybug", keywords: "bug debug issue error"),
        .init(name: "ladybug.fill", keywords: "bug debug issue error"),
        .init(name: "ant", keywords: "bug debug issue"),
        .init(name: "stethoscope", keywords: "diagnose health check debug"),
        .init(name: "bandage", keywords: "fix patch hotfix"),
        .init(name: "cross.case", keywords: "fix patch first aid hotfix"),
        .init(name: "waveform.path.ecg", keywords: "health monitor logs activity"),
        .init(name: "list.bullet.rectangle", keywords: "logs output list"),
        .init(name: "text.alignleft", keywords: "logs text output"),
        .init(name: "lock", keywords: "security secure private"),
        .init(name: "lock.open", keywords: "unlock public"),
        .init(name: "key", keywords: "secret token password auth"),
        .init(name: "shield", keywords: "security protect"),
        .init(name: "shield.lefthalf.filled", keywords: "security protect"),
        .init(name: "exclamationmark.shield", keywords: "security vulnerability alert"),

        // AI and misc
        .init(name: "sparkles", keywords: "ai magic agent claude assistant new"),
        .init(name: "sparkle", keywords: "ai magic agent new"),
        .init(name: "wand.and.stars", keywords: "ai magic agent auto"),
        .init(name: "wand.and.rays", keywords: "ai magic auto"),
        .init(name: "brain", keywords: "ai think agent model"),
        .init(name: "brain.head.profile", keywords: "ai think agent model"),
        .init(name: "lightbulb", keywords: "idea suggestion hint"),
        .init(name: "flame", keywords: "hot fire urgent"),
        .init(name: "cloud", keywords: "cloud deploy server"),
        .init(name: "icloud.and.arrow.up", keywords: "cloud deploy upload publish"),
        .init(name: "icloud.and.arrow.down", keywords: "cloud download fetch"),
        .init(name: "airplane", keywords: "ship launch deploy travel"),

        // Web, devices, and design
        .init(name: "globe", keywords: "web browser internet url open"),
        .init(name: "globe.americas", keywords: "web browser internet url world"),
        .init(name: "network", keywords: "web network internet api"),
        .init(name: "safari", keywords: "web browser url open"),
        .init(name: "safari.fill", keywords: "web browser url open"),
        .init(name: "link", keywords: "url web open href"),
        .init(name: "link.circle", keywords: "url web open href"),
        .init(name: "link.badge.plus", keywords: "url add new"),
        .init(name: "rectangle.on.rectangle", keywords: "windows tabs copy"),
        .init(name: "square.on.square", keywords: "windows copy duplicate"),
        .init(name: "macbook", keywords: "computer laptop mac local"),
        .init(name: "desktopcomputer", keywords: "computer mac local"),
        .init(name: "iphone", keywords: "phone mobile ios"),
        .init(name: "antenna.radiowaves.left.and.right", keywords: "broadcast signal network"),
        .init(name: "building.2", keywords: "company org office"),
        .init(name: "paintbrush", keywords: "design style format lint"),
        .init(name: "paintpalette", keywords: "design color theme"),
        .init(name: "pencil.and.ruler", keywords: "design draw"),
        .init(name: "square.grid.2x2", keywords: "apps grid layout"),
        .init(name: "plus", keywords: "add new create"),
        .init(name: "plus.circle", keywords: "add new create"),
        .init(name: "minus.circle", keywords: "remove subtract"),
        .init(name: "ellipsis.circle", keywords: "more options menu"),
    ]

    /// Every query word must appear in the name or keywords. Ranked: exact name, name prefix, name contains
    /// the query, a word in the name, keywords only. A valid symbol name typed in full is offered even when
    /// it isn't curated.
    static func search(_ query: String) -> [String] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return entries.map(\.name) }
        let typed = words.joined(separator: " ")
        let ranked = entries.compactMap { entry -> (rank: Int, name: String)? in
            let name = entry.name
            guard words.allSatisfy((name + " " + entry.keywords).contains) else { return nil }
            let rank = name == typed ? 0 : name.hasPrefix(typed) ? 1 : name.contains(typed) ? 2
                : words.contains(where: name.contains) ? 3 : 4
            return (rank, name)
        }
        .enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map(\.element.name)
        let custom = query.trimmingCharacters(in: .whitespaces)
        if !ranked.contains(custom), isValid(custom) { return [custom] + ranked }
        return ranked
    }

    static func isValid(_ name: String) -> Bool {
        !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }
}

/// Field-styled button showing the current symbol; opens a searchable grid of `SymbolCatalog`.
struct SymbolPicker: View {
    @Binding var symbol: String
    @State private var isPresented = false

    var body: some View {
        Button { isPresented.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: SymbolCatalog.isValid(symbol) ? symbol : "questionmark")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 20)
                Text(symbol.isEmpty ? "Choose a symbol" : symbol)
                    .font(Tokens.Typo.settingsBody)
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Tokens.Palette.settingsSecondary)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Tokens.Palette.settingsField, in: RoundedRectangle(cornerRadius: Tokens.Radius.settingsField, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Tokens.Radius.settingsField, style: .continuous)
                    .strokeBorder(Tokens.Palette.settingsFieldEdge, lineWidth: 0.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Symbol")
        .accessibilityValue(symbol)
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            SymbolGrid(selection: symbol) { picked in
                symbol = picked
                isPresented = false
            } dismiss: {
                isPresented = false
            }
        }
    }
}

private struct SymbolGrid: View {
    let selection: String
    let pick: (String) -> Void
    let dismiss: () -> Void
    @State private var query = ""
    @State private var hovered: String?
    @FocusState private var searchFocused: Bool

    private var results: [String] { SymbolCatalog.search(query) }
    private static let columns = [GridItem(.adaptive(minimum: 38, maximum: 38), spacing: 6)]

    var body: some View {
        let results = results
        VStack(alignment: .leading, spacing: 10) {
            TextField("Search symbols", text: $query)
                .textFieldStyle(SettingsFieldStyle())
                .focused($searchFocused)
                .onSubmit { results.first.map(pick) }
            ScrollView {
                if results.isEmpty {
                    Text("No symbols match. Type a full SF Symbol name to use any symbol.")
                        .font(Tokens.Typo.rowSubtitle).foregroundStyle(Tokens.Palette.settingsSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, 24)
                } else {
                    LazyVGrid(columns: Self.columns, spacing: 6) {
                        ForEach(results, id: \.self) { name in cell(name, isFirst: name == results.first) }
                    }
                    .padding(2)
                }
            }
            .frame(height: 236)
            .scrollIndicators(.automatic)
            Text(footer(first: results.first))
                .font(Tokens.Typo.codeSmall).foregroundStyle(Tokens.Palette.settingsSecondary)
                .lineLimit(1).truncationMode(.middle)
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { searchFocused = true }
        .onExitCommand(perform: dismiss)
    }

    private func footer(first: String?) -> String {
        if let hovered { return hovered }
        if let first, !query.isEmpty { return "↩ \(first)" }
        return "\(SymbolCatalog.entries.count) symbols"
    }

    private func cell(_ name: String, isFirst: Bool) -> some View {
        let selected = name == selection
        let lit = selected || hovered == name || (isFirst && !query.isEmpty)
        return Button { pick(name) } label: {
            Image(systemName: name)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 38, height: 38)
                .foregroundStyle(.white)
                .background(selected ? Tokens.Palette.accent : .white.opacity(lit ? 0.14 : 0.05),
                            in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? name : (hovered == name ? nil : hovered) }
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }
}
