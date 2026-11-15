//  WHAT: `make: navigation`: the app's destinations and how it moves between them (adaptive, tabs, sidebar or
//        split), the layout service, routes and Device, and the root page shown with them once the app is ready.
//  PIN:  THE PAGES COME FIRST. A destination names a page the project has; one it does not is refused, never
//        written as a placeholder.
//  PIN:  A GATE IS HELD BY SOMETHING REAL. A destination marked `gate` comes with `gate`, a condition over the state of
//        a relay the project has, and each without the other is refused: an app that shows Sign In over nothing, or
//        holds a condition with no page to show, is never written.

import Foundation

struct NavigationMake {
    let input: GraniteAppAgent.Input
    let workspace: Workspace

    func plan() throws -> Plan {
        guard workspace.project != nil else {
            throw GraniteError.refused(["navigation is an app's: call it in the folder with the app's .xcodeproj"])
        }
        var problems: [String] = []
        let index = ProjectIndex(root: workspace.root)
        let layout = AppLayout.detect(workspace)
        var destinations: [Destination] = []
        for line in input.destinations ?? [] where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            do {
                let destination = try DestinationLine.parse(line)
                if destinations.contains(where: { $0.name == destination.name }) {
                    problems.append("the destination `\(destination.name)` is named twice")
                    continue
                }
                for type in [destination.viewType, destination.detailType].compactMap({ $0 }) {
                    if !index.declared.contains(type) {
                        problems.append("`\(type)` is not in the project: make the page first (`make: component`, `type: \(type)`)")
                    } else if index.components[type] == nil, Self.needsArguments(type, index: index) {
                        // A destination is made with no arguments: a kit's view that needs its posts and actions
                        // (loom's FeedView) is shown by a page (Margin, 2026-11-01).
                        let page = type.hasSuffix("View") && type.count > 4 ? String(type.dropLast(4)) : type + "Page"
                        problems.append("`\(type)` is a view that needs values to be made, not a page: make a page that shows it "
                                        + "(`make: component`, `type: \(page)`, `layout: blank`, `body: \(type)(…)` filled from its relays) and name that page here")
                    }
                }
                destinations.append(destination)
            } catch { problems.append("\(error)") }
        }
        if destinations.isEmpty { problems.append("name the app's destinations, one a line: `feed: Feed \"Feed\" house`") }
        let defaults = destinations.filter(\.isDefault).map { "`\($0.name)`" }
        if defaults.count > 1 {
            problems.append(defaults.joined(separator: " and ") + (defaults.count == 2 ? " are both" : " are all") + " marked `default`: one tab is where a plain launch opens, so mark one")
        }
        let gates = destinations.filter { $0.place == .gate }
        if gates.count > 1 {
            problems.append(gates.map { "`\($0.name)`" }.joined(separator: " and ") + (gates.count == 2 ? " are both" : " are all") + " marked `gate`: the app has one gate, so mark the page shown while it holds")
        }
        if !destinations.isEmpty, !destinations.contains(where: { $0.place == .tab }) {
            problems.append("every destination is a sheet or the gate: at least one is a tab, which the sheets go up over and the gate gives way to")
        }
        let gate = readGate(gates.first, index: index, problems: &problems)
        let style = input.style ?? .adaptive
        let root = input.root?.trimmingCharacters(in: .whitespaces) ?? Self.rootPage(layout) ?? "Home"
        let rootView = index.components[root]?.deletingLastPathComponent().appendingPathComponent("\(root)+View.swift")
        if let rootView {
            let text = (try? String(contentsOf: rootView, encoding: .utf8)) ?? ""
            if !text.contains("AppRoot.shared.boot()") {
                problems.append("\(workspace.files.relative(rootView)) is not the root page this agent writes (it does not boot the app), so it is not replaced: name the root with `root`")
            }
        } else {
            problems.append("the root page `\(root)` is not in the project: name it with `root`")
        }
        guard problems.isEmpty, let rootView else { throw GraniteError.refused(problems) }

        var plan = Plan()
        let title = workspace.appName ?? root
        let shape = NavigationTemplates.Shape(destinations)
        plan.write(layout.utility.appendingPathComponent("AppDestination.swift"), NavigationTemplates.destinations(destinations, split: style == .split))
        if layout.isLoom {
            plan.write(layout.ios.appendingPathComponent("PlatformNavigationView.swift"), NavigationTemplates.iOS(style: style, appTitle: title, shape: shape))
            plan.write(layout.macos.appendingPathComponent("PlatformNavigationView.swift"), NavigationTemplates.macOS(style: style, appTitle: title, shape: shape))
        } else {
            // One target builds both platforms here: two files of one name would collide, so both views share a file.
            plan.write(layout.utility.appendingPathComponent("PlatformNavigationView.swift"),
                       NavigationTemplates.iOS(style: style, appTitle: title, shape: shape) + "\n" + NavigationTemplates.macOS(style: style, appTitle: title, shape: shape))
        }

        plan.write(layout.utility.appendingPathComponent("Routes.swift"), NavigationTemplates.routes)
        if index.types["Device"] == nil || index.types["Device"].map({ _ in FileManager.default.fileExists(atPath: layout.utility.appendingPathComponent("Device.swift").path) }) == true {
            plan.write(layout.utility.appendingPathComponent("Device.swift"), NavigationTemplates.device)
        } else {
            plan.notes.append("the project has a Device of its own, so it is kept")
        }
        // The tab a plain launch opens on: the first, or the one marked `default`.
        let first = shape.isPlain ? SwiftName.member(destinations[0].name) : shape.opening
        for (path, text) in NavigationTemplates.layoutService(app: workspace.appName ?? "app", first: first, shape: shape) {
            plan.write(layout.services.appendingPathComponent("LayoutService/\(path)"), text)
        }
        let held = gate.map { RootTemplates.Gate(name: SwiftName.member($0.destination.name), title: $0.destination.title, tab: first,
                                                 condition: $0.condition, relays: $0.relays) }
        plan.write(rootView, RootTemplates.view(root, ready: held.map { .gated($0) } ?? .navigation))
        if let (folder, module) = try workspace.unitTests() {
            // Going somewhere is to another tab: the second destination, or with a default, sheets or a gate the
            // first tab that is not where a plain launch opens.
            let tabs = destinations.filter { $0.place == .tab }.map { SwiftName.member($0.name) }
            let second = shape.isPlain ? SwiftName.member(destinations[destinations.count > 1 ? 1 : 0].name) : tabs.first { $0 != first } ?? first
            plan.write(folder.appendingPathComponent("LayoutOpsTests.swift"),
                       NavigationTemplates.layoutTests(module: module, first: first, second: second, shape: shape),
                       role: .tests)
        }
        if !index.hasRelayClock { plan.write(layout.utility.appendingPathComponent("RelayClock.swift"), UtilityTemplates.relayClock) }
        if let (file, text) = workspace.rootAdding("LayoutService", index: index, plan: plan) { plan.write(file, text) }
        for relay in gate?.relays ?? [] {
            if let (file, text) = workspace.rootAdding(relay.type, index: index, plan: plan) { plan.write(file, text) }
        }

        plan.types = ["AppDestination", "PlatformNavigationView", "LayoutService", "Routes", "Device", root] + (gate == nil ? [] : ["AppGate"])
        switch style {
        case .adaptive: plan.notes.append("a tab bar on a compact iPhone, a sidebar beside the page on iPad and the Mac")
        case .tabs: plan.notes.append("a tab bar on iPhone and iPad, a sidebar on the Mac")
        case .sidebar: plan.notes.append("a sidebar beside the page everywhere; on iPhone it collapses into a list")
        case .split: plan.notes.append("the destinations, the page and its detail side by side; a page opens the detail with `layout.show(detail: id)`, and the Mac window widens for it")
        }
        if style != .split, destinations.contains(where: { $0.detail != nil }) {
            plan.notes.append("a destination's `| Detail` is shown only in the split style, so it was left out")
        }
        if shape.isDefault {
            plan.notes.append("a plain launch opens on `\(first)`, the default, every time; a menu or a page moves the app with `layout.select(.\(first))`")
        } else {
            plan.notes.append("the selected destination persists in LayoutService; a menu or a page moves the app with `layout.select(.\(first))`")
        }
        if let sheet = shape.sheets.first {
            plan.notes.append(shape.sheets.map { "`\($0)`" }.joined(separator: ", ") + (shape.sheets.count == 1 ? " is a sheet" : " are sheets")
                              + " over the tabs, at the large detent with a close button: a page opens one with `layout.present(.\(sheet))`, "
                              + "and `-destination \(sheet)` opens `\(first)` with it up")
        }
        if let gate {
            plan.notes.append("while `\(gate.condition)` holds, the root shows `\(gate.destination.name)` full screen instead of the tabs; "
                              + "a launch with `-destination` naming any other destination opens past it, to check that screen")
        }
        return plan
    }

    /// The gate's page, its condition and the relays the condition reads; nil when there is no gate. Each of the line
    /// and the condition without the other is a problem, and so is a relay the project lacks or a name the condition
    /// cannot see. A call with no gate reads no relays, as before there were gates.
    private func readGate(_ line: Destination?, index: ProjectIndex, problems: inout [String]) -> (destination: Destination, condition: String, relays: [Relay])? {
        let condition = input.gate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let example = "`\"gate\": \"account.state.session == nil\"` with `\"relays\": [\"account: AccountService\"]`"
        guard line != nil || !condition.isEmpty else { return nil }
        let start = problems.count
        if line == nil {
            problems.append("`gate` holds a gate, and no destination is marked `gate`: mark the page shown while it holds, like `auth: SignIn \"Sign In\" person gate`")
        }
        if let line, condition.isEmpty {
            problems.append("`\(line.name)` is marked `gate`, and nothing holds it: give `gate` a condition over a relay's state, like \(example)")
        }
        var relays: [Relay] = []
        for text in input.relays ?? [] where !text.trimmingCharacters(in: .whitespaces).isEmpty {
            do {
                let relay = try RelayLine.parse(text)
                if index.services[relay.type] == nil {
                    problems.append(RelayLine.missing(text, relay: relay, declared: index.declared))
                } else if relays.contains(where: { $0.name == relay.name }) {
                    problems.append("the relay `\(relay.name)` is named twice")
                } else {
                    relays.append(relay)
                }
            } catch { problems.append("\(error)") }
        }
        if !condition.isEmpty {
            if condition.contains("\n") {
                problems.append("`gate` is one condition on one line, like `account.state.session == nil`")
            }
            let code = condition.replacingOccurrences(of: #""(?:[^"\\]|\\.)*""#, with: "\"\"", options: .regularExpression)
            let named = Set(relays.map(\.name))
            let words: Set<String> = ["self", "true", "false", "nil", "try", "await"]
            var said: Set<String> = []
            for name in code.matches(#"(?<![\w.$])([a-z_][A-Za-z0-9_]*)\s*[.(\[]"#) where !named.contains(name) && !words.contains(name) && said.insert(name).inserted {
                let service = index.services.keys.sorted().first { $0.lowercased().hasPrefix(name.lowercased()) }
                problems.append("the gate reads `\(name)`, which is not one of `relays`: name it there"
                                + (service.map { " (`\(name): \($0)`)" } ?? ", after making its service (`make: service`)"))
            }
            let read = relays.filter { relay in code.range(of: #"(?<![\w.$])"# + relay.name + #"\b"#, options: .regularExpression) != nil }
            if read.isEmpty, said.isEmpty {
                problems.append("the gate reads no relay: it is a condition over a relay's state, like \(example)")
            }
            problems += ComponentMake.relayMisuse(in: code, relays: read, index: index).map { "the gate: " + $0 }
            for relay in read {
                guard let service = index.services[relay.type], !service.fields.isEmpty else { continue }
                let missing = Set(code.matches(#"(?<![\w.$])"# + relay.name + #"\.state\.([A-Za-z_]\w*)"#)).filter { service.field($0) == nil }.sorted()
                if !missing.isEmpty {
                    problems.append("the gate reads " + missing.map { "`\(relay.name).state.\($0)`" }.joined(separator: ", ")
                                    + ", which \(relay.type)'s state does not have (it has " + service.fields.map { "`\($0.name)`" }.joined(separator: ", ") + ")")
                }
            }
            relays = read
        }
        guard problems.count == start, let line else { return nil }
        return (line, condition, relays)
    }

    /// The page the App's window opens with: the first call in its `WindowGroup`.
    static func rootPage(_ layout: AppLayout) -> String? {
        guard let app = layout.app, let text = try? String(contentsOf: app, encoding: .utf8),
              let group = text.range(of: "WindowGroup") else { return nil }
        let after = String(text[group.upperBound...])
        return after.matches(
#"\{\s*([A-Z][A-Za-z0-9_]*)\s*[\(\{]"#).first
    }

    /// Whether `type` cannot be made with `\(type)()`: generic, or an initializer or a stored `let` that needs a value.
    static func needsArguments(_ type: String, index: ProjectIndex) -> Bool {
        guard let shape = index.shapes[type], let header = shape.first else { return false }
        if header.contains("\(type)<") { return true }
        let members = shape.dropFirst()
        let inits = members.filter { $0.hasPrefix("init(") || $0.contains(" init(") }
        if !inits.isEmpty {
            // Made with no arguments when some initializer takes none, or only defaulted ones.
            return !inits.contains { signature in
                guard let open = signature.firstIndex(of: "("), let close = signature.lastIndex(of: ")") else { return false }
                let inside = String(signature[signature.index(after: open)..<close])
                return ProjectIndex.topLevel(inside).allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty || $0.contains("=") }
            }
        }
        return members.contains { $0.hasPrefix("let ") && !$0.contains("=") }
    }
}
