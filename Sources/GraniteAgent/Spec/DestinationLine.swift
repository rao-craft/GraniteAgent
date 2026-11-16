//  WHAT: A destinations line: one place the app goes, as the sidebar and the tab bar show it.
//
//            feed: Feed "Feed" house
//            search: Search(scope: .all) "Search" magnifyingglass
//            inbox: Inbox "Inbox" tray | Message
//            seer: Seer "Seer" sparkles default
//            seer: Seer "Seer" SeerMark().frame(width: 30, height: 30) default
//            wallet: Wallet "Wallet" creditcard sheet
//            profile: Profile "Profile" person.crop.circle sheet over models
//            world: World "The World" infinity sheet over seer detents medium large
//            auth: SignIn "Sign In" person gate
//            auth.signup -> auth
//
//        The case, the view (a component, with arguments when it takes any), the title in quotes, its SF Symbol (or in
//        its place a view the app has, in UpperCamelCase, drawn once as the tab's image in its own colours), a
//        word for where it sits when it is not just a tab (`default` the tab a plain launch opens on, `sheet` a sheet
//        over the tabs, `gate` the page shown instead of them while the call's `gate` holds), for a sheet `over` and
//        what a launch that names it puts up under it (a tab or another sheet) and `detents` and the heights it rests
//        at (`medium`, `large`, `fraction(0.6)`, `height(320)`, the first where it goes up), and after a bar the view
//        the detail pane shows beside it in the split style. A line `name -> destination` is a launch alias: another
//        name a launch may give for a destination, dots allowed.

import Foundation

enum DestinationLine {
    /// The words that may follow a destination's symbol.
    static let marks = ["default", "sheet", "gate"]

    static func parse(_ line: String) throws -> Destination {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let colon = text.firstIndex(of: ":") else {
            throw GraniteError.line(line, "a destination is `name: View \"Title\" symbol`, like `feed: Feed \"Feed\" house`")
        }
        let name = text[..<colon].trimmingCharacters(in: .whitespaces)
        guard SwiftName.isMemberName(name) else { throw GraniteError.line(line, "`\(name)` is not a case name (lowerCamelCase)") }
        var rest = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        var detail: String?
        if let bar = LineSplit.firstTop(rest, "|") {
            detail = rest[rest.index(after: bar)...].trimmingCharacters(in: .whitespaces)
            rest = rest[..<bar].trimmingCharacters(in: .whitespaces)
        }
        guard let quote = rest.firstIndex(of: "\""), let end = rest[rest.index(after: quote)...].firstIndex(of: "\"") else {
            throw GraniteError.line(line, "the destination's title goes in quotes, like `\"Feed\"`")
        }
        let view = rest[..<quote].trimmingCharacters(in: .whitespaces)
        let title = String(rest[rest.index(after: quote)..<end])
        var tail = rest[rest.index(after: end)...].drop(while: \.isWhitespace)
        var drawn: String?, drawnType: String?
        if tail.first?.isUppercase == true {
            let (expression, after) = Self.expression(tail)
            guard let type = Self.drawnType(expression) else {
                throw GraniteError.line(line, "`\(expression)` is not a view drawn as the tab's image: a view the app has, like `SeerMark()` "
                                        + "or `SeerMark().frame(width: 30, height: 30)`")
            }
            (drawn, drawnType, tail) = (expression, type, after)
        }
        var words = tail.split(whereSeparator: \.isWhitespace).map(String.init)
        let symbol = drawn != nil || words.isEmpty ? "" : words.removeFirst()
        let (viewText, viewType) = try viewCall(view, in: line)
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { throw GraniteError.line(line, "the title is empty") }
        guard drawn != nil || symbol.range(of: #"^[a-z0-9]+(\.[a-z0-9]+)*$"#, options: .regularExpression) != nil else {
            throw GraniteError.line(line, "after the title comes the destination's SF Symbol, like `house` or `gearshape`, or a view the app has drawn as its image, like `SeerMark()`")
        }
        var place = Destination.Place.tab, isDefault = false, over: String?
        if let at = words.firstIndex(of: "over") {
            let target = at + 1 < words.count ? words[at + 1] : ""
            guard !target.isEmpty, !marks.contains(target), target != "over", target != "detents" else {
                throw GraniteError.line(line, "`over` names what the sheet goes up over when a launch names it, a tab or another sheet, like `sheet over models`")
            }
            guard LaunchAlias.isName(target) else { throw GraniteError.line(line, "`over \(target)`: `\(target)` is not a destination's name") }
            words.removeSubrange(at...(at + 1))
            if words.contains("over") { throw GraniteError.line(line, "`over` is said twice") }
            over = target
        }
        let detents = try Self.detents(&words, in: line)
        for word in words {
            guard marks.contains(word) else {
                throw GraniteError.line(line, "after the SF Symbol comes `default`, `sheet` or `gate`, not `\(word)`")
            }
            guard words.filter({ $0 == word }).count == 1 else { throw GraniteError.line(line, "`\(word)` is said twice") }
            switch word {
            case "default": isDefault = true
            case "sheet": place = .sheet
            default: place = .gate
            }
        }
        if words.contains("sheet"), words.contains("gate") {
            throw GraniteError.line(line, "a destination is a sheet over the tabs or the gate before them, not both")
        }
        if isDefault, place != .tab {
            throw GraniteError.line(line, "`default` names the tab a plain launch opens on, and a \(place.rawValue) is not a tab")
        }
        if let over, place != .sheet {
            throw GraniteError.line(line, "`over \(over)` says what a sheet goes up over when a launch names it, and a \(place.rawValue) is not a sheet: say `sheet over \(over)`")
        }
        if !detents.isEmpty, place != .sheet {
            let said = detents.map(\.word).joined(separator: " ")
            throw GraniteError.line(line, "`detents \(said)` names the heights a sheet rests at, and a \(place.rawValue) is not a sheet: say `sheet detents \(said)`")
        }
        var detailText: String?, detailType: String?
        if let detail { (detailText, detailType) = try viewCall(detail, in: line) }
        return Destination(name: name, view: viewText, viewType: viewType, title: title, symbol: symbol, detail: detailText, detailType: detailType,
                           place: place, isDefault: isDefault, over: over, drawn: drawn, drawnType: drawnType, detents: detents)
    }

    /// The heights after `detents`, read out of `words` up to the next word that says where the destination sits: each
    /// one a height a sheet rests at, none named twice, and `detents` said once.
    static func detents(_ words: inout [String], in line: String) throws -> [SheetDetent] {
        guard let at = words.firstIndex(of: "detents") else { return [] }
        var end = at + 1
        while end < words.count, !marks.contains(words[end]), words[end] != "detents", words[end] != "over" { end += 1 }
        guard end > at + 1 else {
            throw GraniteError.line(line, "`detents` names the heights the sheet rests at, the first where it goes up: \(SheetDetent.forms), like `sheet detents medium large`")
        }
        var detents: [SheetDetent] = []
        for word in words[(at + 1)..<end] {
            guard let detent = SheetDetent(word: word) else {
                throw GraniteError.line(line, "`\(word)` is not a height a sheet rests at: after `detents` come \(SheetDetent.forms)")
            }
            if let problem = detent.problem { throw GraniteError.line(line, "`\(word)`: \(problem)") }
            guard !detents.contains(detent) else { throw GraniteError.line(line, "`\(word)` is named twice after `detents`") }
            detents.append(detent)
        }
        words.removeSubrange(at..<end)
        if words.contains("detents") { throw GraniteError.line(line, "`detents` is said twice") }
        return detents
    }

    /// A view written where the symbol goes, up to the first space outside its parentheses and quotes, and what
    /// follows it: `SeerMark().frame(width: 30, height: 30) default` → the view and ` default`.
    static func expression(_ text: Substring) -> (String, Substring) {
        var depth = 0, quoted = false, index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            if character == "\"" { quoted.toggle() }
            if !quoted {
                if character == "(" { depth += 1 }
                if character == ")" { depth -= 1 }
                if character.isWhitespace, depth == 0 { break }
            }
            index = text.index(after: index)
        }
        return (String(text[..<index]), text[index...])
    }

    /// The type of a view drawn as a tab's image: `SeerMark` for `SeerMark().frame(width: 30, height: 30)`; nil
    /// when the text is not a view made by a call, its parentheses closed, with modifiers after it.
    static func drawnType(_ expression: String) -> String? {
        let type = String(expression.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
        guard SwiftName.isTypeName(type) else { return nil }
        var rest = String(expression.dropFirst(type.count))
        guard rest.hasPrefix("(") else { return nil }
        while !rest.isEmpty {
            guard rest.hasPrefix("("), let close = EventLine.closingParenthesis(rest) else { return nil }
            rest = String(rest[rest.index(after: close)...])
            if rest.isEmpty { return type }
            let name = rest.dropFirst().prefix { $0.isLetter || $0.isNumber || $0 == "_" }
            guard rest.hasPrefix("."), !name.isEmpty else { return nil }
            rest = String(rest.dropFirst(1 + name.count))
        }
        return nil
    }

    /// A line `name -> destination`: another name a launch may give for a destination; nil when the line is a
    /// destination (its name comes before a colon, and an arrow after it belongs to its view).
    static func alias(_ line: String) throws -> LaunchAlias? {
        let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let arrow = text.range(of: "->") else { return nil }
        let name = text[..<arrow.lowerBound].trimmingCharacters(in: .whitespaces)
        guard !name.contains(":"), !name.contains("\"") else { return nil }
        let target = text[arrow.upperBound...].trimmingCharacters(in: .whitespaces)
        let example = "a launch alias is `name -> destination`, like `auth.signup -> auth`"
        guard LaunchAlias.isName(name) else {
            throw GraniteError.line(line, name.isEmpty ? example : "`\(name)` is not a name a launch gives: letters, digits and `_`, in parts joined by `.` or `-`, like `auth.signup`")
        }
        guard LaunchAlias.isName(target) else {
            throw GraniteError.line(line, target.isEmpty ? example : "`\(target)` is not a destination's name: \(example)")
        }
        return LaunchAlias(name: name, target: target)
    }

    /// `Feed` → (`Feed()`, `Feed`); `Feed(kind: .all)` stays as written.
    static func viewCall(_ text: String, in line: String) throws -> (String, String) {
        let type = String(text.prefix { $0.isLetter || $0.isNumber || $0 == "_" })
        guard SwiftName.isTypeName(type) else { throw GraniteError.line(line, "`\(text)` is not a view (a type in UpperCamelCase)") }
        let rest = text.dropFirst(type.count).trimmingCharacters(in: .whitespaces)
        if rest.isEmpty { return ("\(type)()", type) }
        guard rest.hasPrefix("("), let close = EventLine.closingParenthesis(rest), rest.index(after: close) == rest.endIndex else {
            throw GraniteError.line(line, "`\(text)` is not a view call like `Feed` or `Feed(kind: .all)`")
        }
        return ("\(type)\(rest)", type)
    }
}
