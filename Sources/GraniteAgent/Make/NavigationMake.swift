//  WHAT: `make: navigation`: the app's destinations and how it moves between them (adaptive, tabs, sidebar or
//        split), the layout service, routes and Device, and the root page shown with them once the app is ready.
//  PIN:  THE PAGES COME FIRST. A destination names a page the project has; one it does not is refused, never
//        written as a placeholder.
//  PIN:  A GATE IS HELD BY SOMETHING REAL. A destination marked `gate` comes with `gate`, a condition over the state of
//        a relay the project has, and each without the other is refused: an app that shows Sign In over nothing, or
//        holds a condition with no page to show, is never written.
//  PIN:  A LAUNCH NAME OPENS ONE PLACE. An alias (`auth.signup -> auth`) opens a destination exactly as its own name
//        does, so a name that is a destination and an alias, an alias named twice, one that names nothing and a cycle
//        are refused; so is a sheet `over` nothing, over the gate, over itself, or over a sheet that goes up over it.
//  PIN:  WHAT IS DRAWN OVER THE TABS IS THE APP'S. A view drawn as a tab's image and an overlay over the tabs are views
//        the project has; one it does not is refused, as a destination's page is.
//  PIN:  A PAGE THAT MOVES THE APP NAMES PLACES IT HAS. A page may relay the layout before the navigation is made, so
//        the navigation reads every page that relays it: a destination one names that this call does not have, or a
//        part of the layout one reads that this call's layout lacks, is refused with the page named, never left to
//        a build that fails after the turn has moved on.

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
        var aliases: [LaunchAlias] = []
        for line in input.destinations ?? [] where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            do {
                if let alias = try DestinationLine.alias(line) {
                    aliases.append(alias)
                    continue
                }
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
                if let drawn = destination.drawnType, drawn != "Image", !index.declared.contains(drawn) {
                    problems.append("`\(drawn)` is not in the project: the view drawn as `\(destination.name)`'s image is one the app has "
                                    + "(its mark, or a view of its own), or `Image(\"name\")` for an image in its assets")
                }
                destinations.append(destination)
            } catch { problems.append("\(error)") }
        }
        var overlays: [String] = []
        for line in input.overlays ?? [] where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            do {
                let (call, type) = try DestinationLine.viewCall(line.trimmingCharacters(in: .whitespaces), in: line)
                if !index.declared.contains(type) {
                    problems.append("the overlay `\(type)` is not in the project: make the page first (`make: component`, `type: \(type)`)")
                } else if call == "\(type)()", index.components[type] == nil, Self.needsArguments(type, index: index) {
                    problems.append("the overlay `\(type)` is a view that needs values to be made: make a page that shows it "
                                    + "(`make: component`, `layout: blank`, `body: \(type)(…)`) and name that page here")
                }
                overlays.append(call)
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
        let resolved = Self.resolve(aliases, destinations: destinations, problems: &problems)
        Self.readHeights(resolved, destinations: destinations, problems: &problems)
        let overNotes = Self.readOver(&destinations, aliases: resolved, problems: &problems)
        let gate = readGate(gates.first, index: index, problems: &problems)
        let style = input.style ?? .adaptive
        let root = input.root?.trimmingCharacters(in: .whitespaces) ?? Self.rootPage(layout) ?? "Home"
        Self.readPages(index, layout: NavigationTemplates.layoutSurface(NavigationTemplates.Shape(destinations, aliases: resolved)),
                       destinations: destinations, root: root, problems: &problems)
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
        var shape = NavigationTemplates.Shape(destinations, aliases: resolved)
        let tint = input.tint.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        shape.iconsOnly = input.tabBar == .icons
        shape.tint = tint
        shape.feedback = input.tabFeedback?.sensory
        shape.overlays = overlays
        plan.write(layout.utility.appendingPathComponent("AppDestination.swift"), NavigationTemplates.destinations(destinations, split: style == .split, aliases: resolved))
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
        let held = gate.map { gate in
            RootTemplates.Gate(name: SwiftName.member(gate.destination.name), title: gate.destination.title, tab: first, condition: gate.condition,
                               relays: gate.relays, aliases: resolved.filter { $0.target == gate.destination.name }.map(\.name))
        }
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
        // With `detents` each sheet's heights get a note of their own, so the large detent is not said of them all.
        let closing = shape.hasDetents ? "with a close button" : "at the large detent with a close button"
        if let sheet = shape.sheets.first, !shape.isStacked {
            plan.notes.append(shape.sheets.map { "`\($0)`" }.joined(separator: ", ") + (shape.sheets.count == 1 ? " is a sheet" : " are sheets")
                              + " over the tabs, \(closing): a page opens one with `layout.present(.\(sheet))`, "
                              + "and `-destination \(sheet)` opens `\(first)` with it up")
        } else if let sheet = shape.sheets.first {
            plan.notes.append(shape.sheets.map { "`\($0)`" }.joined(separator: ", ") + (shape.sheets.count == 1 ? " is a sheet" : " are sheets")
                              + ", \(closing): a page puts one up over whatever is up, the tab or another sheet, with "
                              + "`layout.present(.\(sheet))`, and its close button or a swipe takes down only it")
            plan.notes += overNotes
        }
        if shape.hasDetents {
            let named = shape.sheets.compactMap { sheet in shape.detents[sheet].map { "`\(sheet)` at " + $0.map(\.word).joined(separator: " then ") } }
            let large = shape.sheets.filter { shape.detents[$0] == nil }.map { "`\($0)`" }
            plan.notes.append("sheet heights: " + named.joined(separator: "; ") + ". Each goes up at the first its line names, on a launch too, "
                              + "with the drag indicator showing, and rests where the person drags it (`AppDestination.detents`, "
                              + "`.presentationDetents(_:selection:)`)" + (large.isEmpty ? "" : "; " + large.joined(separator: ", ")
                              + (large.count == 1 ? " goes" : " go") + " up at the large detent alone"))
        }
        if shape.hasAliasDetents {
            plan.notes.append("alias heights: " + shape.aliasDetents.map { alias in
                "`-destination \(alias.name)` puts " + alias.sheets.map { "`\($0)`" }.joined(separator: " and ") + " up at \(alias.detent.word)"
            }.joined(separator: "; ") + ", once (`AppDestination.launchDetent(for:)`); after the launch each sheet goes up at its first")
        }
        if shape.hasBare {
            plan.notes.append(shape.bare.map { "`\($0)`" }.joined(separator: ", ") + (shape.bare.count == 1 ? " draws its own close (`bare`): its sheet adds" : " draw their own close (`bare`): their sheets add")
                              + " no close button, and a swipe down still closes " + (shape.bare.count == 1 ? "it" : "them"))
        }
        if !resolved.isEmpty {
            let pairs = Dictionary(grouping: resolved, by: \.target).sorted { a, b in
                (destinations.firstIndex { $0.name == a.key } ?? 0) < (destinations.firstIndex { $0.name == b.key } ?? 0)
            }
            plan.notes.append("launch aliases: " + pairs.map { target, names in
                names.map { "`\($0.name)`" }.joined(separator: ", ") + " open" + (names.count == 1 ? "s" : "") + " `\(target)`"
                    + (target == gates.first?.name ? " (on the gate)" : "")
            }.joined(separator: "; ") + ". Each opens exactly as its destination's own name does, and the name stays in the `destination` default, "
                + "so the page reads it with `UserDefaults.standard.string(forKey: \"destination\")` and opens its own inner state; "
                + "`AppDestination.launchNames` lists every name a launch may give")
        }
        if let gate {
            plan.notes.append("while `\(gate.condition)` holds, the root shows `\(gate.destination.name)` full screen instead of the tabs; "
                              + "a launch with `-destination` naming any other destination opens past it, to check that screen")
        }
        for destination in destinations {
            guard let drawn = destination.drawn else { continue }
            plan.notes.append("`\(destination.name)`'s image is `\(drawn)`, drawn once at the screen's scale in its own colours "
                              + "(`AppDestination.image(scale:)`), so the tab bar never tints it")
        }
        let hasTabBar = style == .adaptive || style == .tabs
        if hasTabBar {
            if shape.iconsOnly { plan.notes.append("the tab bar shows each tab's image alone, with an empty title as `Tab(\"\", …)` writes it") }
            if let tint {
                plan.notes.append("the selected tab takes `\(tint)`" + (shape.sheets.isEmpty ? "" : ", and so does each sheet's stack (iOS), as sheets presented from "
                                  + "inside the tinted tab view would; the gate keeps the system's"))
            }
            if let feedback = input.tabFeedback {
                plan.notes.append("a tab change on iPhone gives a \(feedback.rawValue) impact (`.sensoryFeedback(\(feedback.sensory), trigger: layout.state.destination)`)")
            }
        } else if shape.iconsOnly || tint != nil || input.tabFeedback != nil {
            plan.notes.append("`tabBar`, `tint` and `tabFeedback` dress a tab bar, and the \(style.rawValue) style has none, so they were left out")
        }
        if !overlays.isEmpty {
            plan.notes.append(overlays.map { "`\($0)`" }.joined(separator: ", ") + (overlays.count == 1 ? " is" : " are")
                              + " drawn over the tabs, under every sheet; an overlay reads `layout.state.destination` for the tab that is up, "
                              + "and lets touches through where it draws nothing (`allowsHitTesting`)")
        }
        return plan
    }

    /// Each alias with the destination it opens, read through any alias it names. A name that is also a destination,
    /// an alias named twice, one that names neither a destination nor an alias, and a cycle are problems.
    static func resolve(_ aliases: [LaunchAlias], destinations: [Destination], problems: inout [String]) -> [LaunchAlias] {
        let names = destinations.map(\.name)
        var unique: [LaunchAlias] = []
        for alias in aliases {
            if names.contains(alias.name) {
                problems.append("`\(alias.name)` is a destination and an alias: a launch name opens one place, so give the alias a name of its own")
            } else if unique.contains(where: { $0.name == alias.name }) {
                problems.append("the alias `\(alias.name)` is named twice")
            } else {
                unique.append(alias)
            }
        }
        let table = Dictionary(uniqueKeysWithValues: unique.map { ($0.name, $0.target) })
        var resolved: [LaunchAlias] = []
        var cycles: Set<[String]> = []
        for alias in unique {
            var walked = [alias.name]
            var target = alias.target
            // An alias of an alias opens what that one opens, at its height when it names none of its own.
            var detent = alias.detent
            while let next = table[target], !walked.contains(target) {
                walked.append(target)
                detent = detent ?? unique.first { $0.name == target }?.detent
                target = next
            }
            if let start = walked.firstIndex(of: target) {
                let cycle = Array(walked[start...])
                if cycles.insert(cycle.sorted()).inserted {
                    problems.append("`" + (cycle + [target]).joined(separator: " -> ") + "` is a cycle: an alias opens a destination, so one of them names it")
                }
            } else if names.contains(target) {
                resolved.append(LaunchAlias(name: alias.name, target: target, detent: detent))
            } else if walked.count == 1 {
                problems.append("`\(alias.name) -> \(alias.target)`: `\(alias.target)` is neither a destination nor an alias (the destinations are "
                                + names.map { "`\($0)`" }.joined(separator: ", ") + ")")
            }
        }
        return resolved
    }

    /// Each sheet's `over`, read through an alias to the destination it names, and a note for each launch that puts up
    /// more than the sheet. One over no destination, over the gate, over itself, or over a sheet that goes up over it
    /// is a problem.
    /// A height an alias names is one its sheet lists: an alias's height on a tab or the gate, on a sheet that lists no
    /// heights, or one its sheet does not list is a problem.
    static func readHeights(_ aliases: [LaunchAlias], destinations: [Destination], problems: inout [String]) {
        for alias in aliases {
            guard let detent = alias.detent, let destination = destinations.first(where: { $0.name == alias.target }) else { continue }
            let opens = "`\(alias.name)` opens `\(alias.target)` at \(detent.word)"
            if destination.place != .sheet {
                problems.append(opens + ", and `\(alias.target)` is " + (destination.place == .gate ? "the gate" : "a tab")
                                + ": a height is a sheet's, so drop `\(detent.word)` from the alias")
            } else if destination.detents.isEmpty {
                problems.append(opens + ", and `\(alias.target)` names no `detents`, so it goes up large: give it `detents` with \(detent.word) among them, "
                                + "or drop `\(detent.word)` from the alias")
            } else if !destination.detents.contains(detent) {
                problems.append(opens + ", a height `\(alias.target)` does not rest at (it rests at "
                                + destination.detents.map(\.word).joined(separator: ", ") + "): name one of them")
            }
        }
    }

    static func readOver(_ destinations: inout [Destination], aliases: [LaunchAlias], problems: inout [String]) -> [String] {
        var notes: [String] = []
        for index in destinations.indices {
            guard let over = destinations[index].over else { continue }
            let name = destinations[index].name
            let target = aliases.first { $0.name == over }?.target ?? over
            guard let under = destinations.first(where: { $0.name == target }) else {
                problems.append("`\(name)` goes up over `\(over)`, which is not a destination (the destinations are "
                                + destinations.map { "`\($0.name)`" }.joined(separator: ", ") + ")")
                continue
            }
            if under.place == .gate {
                problems.append("`\(name)` goes up over `\(target)`, the gate: a sheet goes up over a tab or another sheet")
            } else if target == name {
                problems.append("`\(name)` goes up over itself: a sheet goes up over a tab or another sheet")
            } else {
                destinations[index].over = target
                if target != over { notes.append("`\(name)` goes up over `\(target)`, the destination `\(over)` opens") }
            }
        }
        var said: Set<[String]> = []
        for destination in destinations where destination.over != nil {
            var chain = [destination.name]
            var next = destination.over
            while let name = next, let under = destinations.first(where: { $0.name == name }), under.place == .sheet {
                if let start = chain.firstIndex(of: name) {
                    let cycle = Array(chain[start...])
                    if said.insert(cycle.sorted()).inserted {
                        problems.append("`" + (cycle + [name]).map { $0 }.joined(separator: "` over `") + "` is a cycle: one of them goes up over a tab")
                    }
                    chain = []
                    break
                }
                chain.append(name)
                next = under.over
            }
            if chain.count > 1 || (chain.count == 1 && destination.over != nil) {
                let tab = next.flatMap { name in destinations.first { $0.name == name && $0.place == .tab }?.name }
                let sheets = chain.reversed().map { "`\($0)`" }
                if !chain.isEmpty, let tab {
                    notes.append("`-destination \(destination.name)` selects `\(tab)`" + (sheets.count > 1 ? " and puts up " + sheets.joined(separator: ", then ") : " with `\(destination.name)` up")
                                 + ", unanimated, as if the person had gone there")
                } else if chain.count > 1 {
                    notes.append("`-destination \(destination.name)` puts up " + sheets.joined(separator: ", then ") + ", unanimated, over the tab a plain launch opens on")
                }
            }
        }
        return notes
    }

    /// Each page that relays the layout, read against the layout this call writes. A page may relay it before the
    /// navigation is made (`NavigationTemplates.unmadeLayout`), so each destination it names through the relay
    /// (`layout.present(.wallet)`, `layout.select(.seer)`, `layout.set(.destination(.seer))`,
    /// `layout.state.destination == .seer`) is one of these, and each part of the layout it reads is one this layout
    /// has: `present` and `closeSheet` come with a sheet, `sheet` with sheets that go up one at a time, `sheets` with
    /// sheets one over another. The root page, which this call writes, is not read.
    static func readPages(_ index: ProjectIndex, layout: ProjectIndex.ServiceInfo, destinations: [Destination], root: String, problems: inout [String]) {
        guard !destinations.isEmpty else { return }
        let names = destinations.map(\.name)
        let own = Set(layout.entries).union(["set", "binding", "state", "isLoaded", "center", "preload", "restore"])
        for (page, file) in index.components.sorted(by: { $0.key < $1.key }) where page != root {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let relays = text.matches(#"@Relay(?:\([^)]*\))?\s+(?:(?:public|private|fileprivate|internal)\s+)?var\s+(\w+)\s*:\s*\#(layout.name)\b"#)
            guard !relays.isEmpty else { continue }
            // The page's own files, the one that declares it and those that extend it, without their strings and comments.
            let code = ProjectIndex.swiftFiles(under: file.deletingLastPathComponent(), skipping: []).compactMap { other -> String? in
                guard let source = try? String(contentsOf: other, encoding: .utf8) else { return nil }
                return other == file || source.range(of: #"\bextension\s+\#(page)\b"#, options: .regularExpression) != nil ? source : nil
            }.joined(separator: "\n")
                .replacingOccurrences(of: #""(?:[^"\\\n]|\\.)*""#, with: "\"\"", options: .regularExpression)
                .replacingOccurrences(of: #"//[^\n]*"#, with: "", options: .regularExpression)
            var named: [(name: String, use: String)] = [], said: Set<String> = []
            for relay in relays {
                let at = #"(?<![\w.])"# + relay + #"\s*\.\s*"#
                for match in code.groups(at + #"(present|select)\s*\(\s*\.([a-z_]\w*)"#) where match.count == 2 {
                    named.append((match[1], "`\(relay).\(match[0])(.\(match[1]))`"))
                }
                for match in code.groups(at + #"set\s*\(\s*\.(destination|sheet)\s*\(\s*\.([a-z_]\w*)"#) where match.count == 2 {
                    named.append((match[1], "`\(relay).set(.\(match[0])(.\(match[1])))`"))
                }
                for match in code.groups(at + #"state\s*\.\s*(destination|sheet)\s*([!=]=)\s*\.([a-z_]\w*)"#) where match.count == 3 {
                    named.append((match[2], "`\(relay).state.\(match[0]) \(match[1]) .\(match[2])`"))
                }
                for member in code.matches(at + #"([A-Za-z_]\w*)"#) where !own.contains(member) && said.insert(member).inserted {
                    problems.append("`\(page)` calls `\(relay).\(member)`, which " + (NavigationTemplates.unmadeLayout.entries.contains(member)
                        ? "the layout has once a destination is a `sheet`: mark the one it " + (member == "present" ? "puts up" : "is shown in") + " `sheet`"
                        : "this navigation's layout does not have") + ", or remake `\(page)` without it")
                }
                for field in code.matches(at + #"state\s*\.\s*([A-Za-z_]\w*)"#) where layout.field(field) == nil && said.insert("state." + field).inserted {
                    let reads = "`\(page)` reads `\(relay).state.\(field)`"
                    if field == "sheet", layout.field("sheets") != nil {
                        problems.append(reads + ", and these sheets go up one over another (`over`): the layout holds `sheets`, the lowest first, "
                                        + "so read `\(relay).state.sheets.last`, or remake `\(page)` without it")
                    } else if field == "sheets", layout.field("sheet") != nil {
                        problems.append(reads + ", the sheets one over another that `over` makes, and these go up one at a time: read "
                                        + "`\(relay).state.sheet`, or give a sheet's line `over`")
                    } else {
                        problems.append(reads + ", which " + (NavigationTemplates.unmadeLayout.field(field) != nil ? "the layout holds once a destination is a `sheet`"
                                                              : "this navigation's layout does not hold") + ", or remake `\(page)` without it")
                    }
                }
            }
            var missing: [(name: String, use: String)] = []
            for use in named where !names.contains(use.name) && !missing.contains(where: { $0.name == use.name }) { missing.append(use) }
            if !missing.isEmpty {
                problems.append("`\(page)` goes to " + missing.map { "`.\($0.name)` (\($0.use))" }.joined(separator: " and ")
                                + (missing.count == 1 ? ", which is not a destination" : ", which are not destinations") + ": add "
                                + (missing.count == 1 ? "it" : "each") + " to `destinations`, or remake `\(page)` without "
                                + (missing.count == 1 ? "it" : "them") + " (the destinations are " + names.map { "`\($0)`" }.joined(separator: ", ") + ")")
            }
        }
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
