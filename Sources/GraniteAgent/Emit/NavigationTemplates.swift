//  WHAT: The app's navigation: its destinations, the platform navigation views (a tab bar on a compact iPhone, a
//        sidebar beside the page on iPad and the Mac, three columns in the split style), the layout service that
//        holds where the app is (persisted destination, compact or expanded, the detail pane's selection, the Mac
//        window widened in a main-actor hop), routes over Granite's router, and what the app runs on.
//  PIN:  THE DESTINATION LIVES IN A SERVICE. A menu, a key or another page moves the app (`layout.select(.feed)`),
//        so the selection is LayoutService's, not the navigation view's (skill §3).
//  PIN:  A CALL WITH NO `default`, `sheet` OR `gate` WRITES WHAT IT WROTE BEFORE THOSE WORDS, byte for byte: every
//        addition below is gated on the `Shape` saying it.

import Foundation

enum NavigationTemplates {
    /// What the words after the destinations' symbols make of the navigation: the tab a plain launch opens on, the
    /// sheets over the tabs and the gate before them.
    struct Shape: Equatable, Sendable {
        /// The tab a plain launch opens on, as its case: the one marked `default`, else the first tab.
        var opening: String
        /// Whether a line said `default`.
        var isDefault: Bool
        /// The sheets, as their cases.
        var sheets: [String]
        /// The gate, as its case.
        var gate: String?

        init(_ destinations: [Destination]) {
            let tabs = destinations.filter { $0.place == .tab }
            let opening = tabs.first(where: \.isDefault) ?? tabs.first ?? destinations.first
            self.opening = opening.map { SwiftName.member($0.name) } ?? ""
            isDefault = tabs.contains(where: \.isDefault)
            sheets = destinations.filter { $0.place == .sheet }.map { SwiftName.member($0.name) }
            gate = destinations.first { $0.place == .gate }.map { SwiftName.member($0.name) }
        }

        /// No line said `default`, `sheet` or `gate`: the navigation is written as it was before those words.
        var isPlain: Bool { !isDefault && sheets.isEmpty && gate == nil }
        /// Whether some destination is not a tab, so the tab bar and the sidebar list `AppDestination.tabs`.
        var hasNonTabs: Bool { !sheets.isEmpty || gate != nil }
        /// What the tab bar and the sidebar list.
        var listed: String { hasNonTabs ? "AppDestination.tabs" : "AppDestination.allCases" }
    }

    // MARK: - Destinations

    static func destinations(_ destinations: [Destination], split: Bool) -> String {
        let shape = Shape(destinations)
        var code = Code()
        code.line("import SwiftUI")
        code.line()
        if shape.hasNonTabs {
            code.doc("The places the app goes, each with its title, its symbol and its page: the tabs its tab bar and its sidebar list"
                     + (shape.sheets.isEmpty ? "" : ", the sheets that go up over them") + (shape.gate == nil ? "" : ", the gate shown before them") + ".")
        } else {
            code.line("/// The places the app goes: what its tab bar and its sidebar list, each with its title, its symbol and its page.")
        }
        code.open("enum AppDestination: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {")
        for destination in destinations { code.line("case \(SwiftName.member(destination.name))") }
        code.line()
        code.line("var id: Self { self }")
        code.line()
        code.line("/// The destination a launch asks for with `-destination <name>`: how UI tests and screenshots open a page.")
        code.scope("static var launchArgument: AppDestination? {") { code in
            code.line("UserDefaults.standard.string(forKey: \"destination\").flatMap(AppDestination.init(rawValue:))")
        }
        code.line()
        if shape.hasNonTabs { places(&code, shape) }
        code.line("/// The destination's name, as the tab bar and the sidebar show it.")
        code.scope("var title: String {") { code in
            code.switchOn("self") { code in
                for destination in destinations {
                    code.line("case .\(SwiftName.member(destination.name)): String(localized: \"\(SwiftName.escaped(destination.title))\")")
                }
            }
        }
        code.line()
        code.line("/// The SF Symbol beside its name.")
        code.scope("var symbol: String {") { code in
            code.switchOn("self") { code in
                for destination in destinations { code.line("case .\(SwiftName.member(destination.name)): \"\(destination.symbol)\"") }
            }
        }
        code.line()
        code.line("/// The page it shows.")
        code.line("@MainActor @ViewBuilder")
        code.scope("var view: some View {") { code in
            code.switchOn("self") { code in
                for destination in destinations { code.line("case .\(SwiftName.member(destination.name)): \(destination.view)") }
            }
        }
        if split {
            code.line()
            code.line("/// What the detail pane shows beside the page, in the split style.")
            code.line("@MainActor @ViewBuilder")
            code.scope("var detail: some View {") { code in
                code.switchOn("self") { code in
                    let detailed = destinations.filter { $0.detail != nil }
                    for destination in detailed { code.line("case .\(SwiftName.member(destination.name)): \(destination.detail!)") }
                    if detailed.count < destinations.count {
                        code.line("default: ContentUnavailableView(\"Nothing Selected\", systemImage: \"sidebar.right\")")
                    }
                }
            }
        }
        code.close()
        return code.text
    }

    // MARK: - The navigation views

    static func iOS(style: GraniteStyle, appTitle: String, shape: Shape? = nil) -> String {
        let shape = shape ?? Shape([])
        var code = Code()
        code.line("#if os(iOS)")
        code.line("import Granite")
        code.line("import SwiftUI")
        code.line()
        switch style {
        case .adaptive: code.line("/// The app's navigation on iPhone and iPad: a tab bar on a compact width, a sidebar beside the page on a regular one.")
        case .tabs: code.line("/// The app's navigation on iPhone and iPad: a tab bar of its destinations.")
        case .sidebar: code.line("/// The app's navigation on iPhone and iPad: a sidebar of its destinations beside the page; on iPhone it collapses into a list.")
        case .split: code.line("/// The app's navigation on iPhone and iPad: its destinations, the page and its detail, side by side.")
        }
        code.open("struct PlatformNavigationView: View {")
        code.line("@Relay var layout: LayoutService")
        code.line("@StateObject private var clock = RelayClock([RelayClock.on(LayoutService.self)])")
        code.line("@Environment(\\.horizontalSizeClass) private var horizontalSizeClass")
        code.line()
        code.open("var body: some View {")
        switch style {
        case .adaptive:
            code.open("Group {")
            code.open("if horizontalSizeClass == .compact {")
            code.line("tabs")
            code.middle("} else {")
            code.line("sidebar")
            code.close()
            code.close()
        case .tabs: code.line("tabs")
        case .sidebar: code.line("sidebar")
        case .split: code.line("columns")
        }
        code.scope(".onChange(of: horizontalSizeClass, initial: true) { _, sizeClass in") { code in
            code.line("layout.set(.style(sizeClass == .compact ? .compact : .expanded))")
        }
        if !shape.sheets.isEmpty { sheetHost(&code, mac: false) }
        code.close()
        if style == .adaptive || style == .tabs {
            code.line()
            code.scope("private var tabs: some View {") { code in
                code.scope("TabView(selection: layout.binding(\\.destination) { .destination($0) }) {") { code in
                    code.scope("ForEach(\(shape.listed)) { destination in") { code in
                        code.scope("NavigationStack {") { $0.line("destination.view") }
                        code.line(".tabItem { Label(destination.title, systemImage: destination.symbol) }")
                        code.line(".tag(destination)")
                    }
                }
            }
        }
        if style == .adaptive || style == .sidebar {
            code.line()
            code.scope("private var sidebar: some View {") { code in
                code.open("NavigationSplitView {")
                sidebarList(&code, title: appTitle, listed: shape.listed)
                code.middle("} detail: {")
                code.scope("NavigationStack {") { $0.line("layout.state.destination.view") }
                code.close()
            }
        }
        if style == .split {
            code.line()
            code.scope("private var columns: some View {") { code in
                code.open("NavigationSplitView {")
                sidebarList(&code, title: appTitle, listed: shape.listed)
                code.middle("} content: {")
                code.scope("NavigationStack {") { $0.line("layout.state.destination.view") }
                code.middle("} detail: {")
                code.line("layout.state.destination.detail")
                code.close()
            }
        }
        selection(&code)
        code.close()
        code.line("#endif")
        return code.text
    }

    static func macOS(style: GraniteStyle, appTitle: String, shape: Shape? = nil) -> String {
        let shape = shape ?? Shape([])
        var code = Code()
        code.line("#if os(macOS)")
        code.line("import Granite")
        code.line("import SwiftUI")
        code.line()
        code.line(style == .split
                  ? "/// The app's navigation on the Mac: its destinations, the page and its detail side by side; the window widens when the detail opens."
                  : "/// The app's navigation on the Mac: a sidebar of its destinations beside the page.")
        code.open("struct PlatformNavigationView: View {")
        code.line("@Relay var layout: LayoutService")
        code.line("@StateObject private var clock = RelayClock([RelayClock.on(LayoutService.self)])")
        code.line()
        code.open("var body: some View {")
        code.open("NavigationSplitView {")
        sidebarList(&code, title: appTitle, listed: shape.listed)
        if style == .split {
            code.middle("} content: {")
            code.scope("NavigationStack {") { $0.line("layout.state.destination.view") }
            code.middle("} detail: {")
            code.line("layout.state.destination.detail")
        } else {
            code.middle("} detail: {")
            code.scope("NavigationStack {") { $0.line("layout.state.destination.view") }
        }
        code.close()
        code.line(".frame(minWidth: LayoutService.minimumWidth, minHeight: LayoutService.minimumHeight)")
        code.line(".onAppear { layout.set(.style(.expanded)) }")
        if style == .split {
            code.scope(".onChange(of: layout.state.detail) { _, detail in") { code in
                code.line("LayoutService.resizeWindow(width: detail == nil ? LayoutService.compactWidth : LayoutService.expandedWidth)")
            }
        }
        if !shape.sheets.isEmpty { sheetHost(&code, mac: true) }
        code.close()
        selection(&code)
        code.close()
        code.line("#endif")
        return code.text
    }

    private static func sidebarList(_ code: inout Code, title: String, listed: String) {
        code.scope("List(\(listed), selection: sidebarSelection) { destination in") { code in
            code.line("Label(destination.title, systemImage: destination.symbol)")
            code.line("    .tag(destination)")
        }
        code.line(".navigationTitle(\"\(SwiftName.escaped(title))\")")
        code.line(".navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)")
    }

    /// The sheet over the tabs, from LayoutService's `sheet`: the page in a stack of its own, at the large detent,
    /// closed by its button or a swipe down (the binding writes nil back), and on the Mac at a window's size.
    private static func sheetHost(_ code: inout Code, mac: Bool) {
        code.scope(".sheet(item: layout.binding(\\.sheet) { .sheet($0) }) { destination in") { code in
            code.scope("NavigationStack {") { code in
                code.line("destination.view")
                code.indent()
                code.scope(".toolbar {") { code in
                    code.scope("ToolbarItem(placement: .cancellationAction) {") { code in
                        code.line("Button(\"Close\", systemImage: \"xmark\") { layout.closeSheet() }")
                    }
                }
                code.dedent()
            }
            if mac { code.line(".frame(minWidth: Routes.windowSize.width, minHeight: Routes.windowSize.height)") }
            code.line(".presentationDetents([.large])")
        }
    }

    /// Which destinations are tabs, which are sheets and which is the gate, and the launch rule past the gate.
    private static func places(_ code: inout Code, _ shape: Shape) {
        let others = (shape.gate.map { [$0] } ?? []) + shape.sheets
        var said: [String] = []
        if !shape.sheets.isEmpty {
            said.append(shape.sheets.map { "`.\($0)`" }.joined(separator: ", ") + (shape.sheets.count == 1 ? " goes up as a sheet over them" : " go up as sheets over them"))
        }
        if let gate = shape.gate { said.append("`.\(gate)` is shown instead of them while the gate holds") }
        code.doc("Whether the tab bar and the sidebar list it: " + said.joined(separator: "; ") + ".")
        code.scope("var isTab: Bool {") { code in
            code.switchOn("self") { code in
                code.line("case " + others.map { ".\($0)" }.joined(separator: ", ") + ": false")
                code.line("default: true")
            }
        }
        code.line()
        code.line("/// The tabs, in their order: what the tab bar and the sidebar list.")
        code.line("static var tabs: [AppDestination] { allCases.filter(\\.isTab) }")
        code.line()
        if let first = shape.sheets.first {
            code.line("/// Whether it goes up as a sheet over the tabs: a page opens it with `layout.present(.\(first))`.")
            code.scope("var isSheet: Bool {") { code in
                code.switchOn("self") { code in
                    code.line("case " + shape.sheets.map { ".\($0)" }.joined(separator: ", ") + ": true")
                    code.line("default: false")
                }
            }
            code.line()
        }
        if let gate = shape.gate {
            let another = shape.opening
            code.line("/// The page shown full screen instead of the tabs while the gate holds.")
            code.line("static let gate: AppDestination = .\(gate)")
            code.line()
            code.line("/// Whether a launch that asks for `destination` opens past the gate. One that names any destination but the gate's")
            code.line("/// own (`-destination \(another)`) does, so UI tests and screenshots reach every screen with no sign-in and no tap;")
            code.line("/// with no `-destination`, or `-destination \(gate)`, the gate holds by its condition.")
            code.scope("static func opensPastGate(_ destination: AppDestination?) -> Bool {") { code in
                code.line("guard let destination else { return false }")
                code.line("return destination != gate")
            }
            code.line()
        }
    }

    private static func selection(_ code: inout Code) {
        code.line()
        code.line("/// The sidebar's selection: one destination is always chosen.")
        code.scope("private var sidebarSelection: Binding<AppDestination?> {") { code in
            code.scope("Binding(get: { layout.state.destination }, set: { destination in", close: "})") { code in
                code.line("if let destination { layout.set(.destination(destination)) }")
            }
        }

    }
}
