//  WHAT: The app's navigation: its destinations, the platform navigation views (a tab bar on a compact iPhone, a
//        sidebar beside the page on iPad and the Mac, three columns in the split style), the layout service that
//        holds where the app is (persisted destination, compact or expanded, the detail pane's selection, the Mac
//        window widened in a main-actor hop), routes over Granite's router, and what the app runs on.
//  PIN:  THE DESTINATION LIVES IN A SERVICE. A menu, a key or another page moves the app (`layout.select(.feed)`),
//        so the selection is LayoutService's, not the navigation view's (skill §3).
//  PIN:  A CALL WITH NO `default`, `sheet` OR `gate` WRITES WHAT IT WROTE BEFORE THOSE WORDS, byte for byte: every
//        addition below is gated on the `Shape` saying it. So does a call with no launch alias and no `over`
//        (`SameBytesTests` holds every earlier call to its bytes), and one with no drawn image, `tabBar`, `tint`,
//        `tabFeedback` or `overlays`, and one whose sheets name no `detents`.

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
        /// The launch aliases, each with the case of the destination it opens.
        var aliases: [LaunchAlias] = []
        /// What each sheet whose line says `over` goes up over when a launch names it, by their cases.
        var over: [String: String] = [:]
        /// Whether a line draws a view the app has as its image, in the symbol's place.
        var isDrawn = false
        /// Whether a tab bar item shows its image alone (`tabBar: icons`).
        var iconsOnly = false
        /// The colour of the tab bar's selected item, a Swift expression (`tint`).
        var tint: String?
        /// The feedback a tab change gives on iPhone, as SwiftUI writes it (`tabFeedback`).
        var feedback: String?
        /// Views drawn over the tabs, bottom to top (`overlays`).
        var overlays: [String] = []
        /// The heights each sheet whose line says `detents` rests at, the first where it goes up, by their cases.
        var detents: [String: [SheetDetent]] = [:]

        init(_ destinations: [Destination], aliases: [LaunchAlias] = []) {
            let tabs = destinations.filter { $0.place == .tab }
            let opening = tabs.first(where: \.isDefault) ?? tabs.first ?? destinations.first
            self.opening = opening.map { SwiftName.member($0.name) } ?? ""
            isDefault = tabs.contains(where: \.isDefault)
            sheets = destinations.filter { $0.place == .sheet }.map { SwiftName.member($0.name) }
            gate = destinations.first { $0.place == .gate }.map { SwiftName.member($0.name) }
            self.aliases = aliases.map { LaunchAlias(name: $0.name, target: SwiftName.member($0.target)) }
            for destination in destinations where destination.place == .sheet {
                if let under = destination.over { over[SwiftName.member(destination.name)] = SwiftName.member(under) }
                if !destination.detents.isEmpty { detents[SwiftName.member(destination.name)] = destination.detents }
            }
            isDrawn = destinations.contains { $0.drawn != nil }
        }

        /// No line said `default`, `sheet` or `gate`: the navigation is written as it was before those words.
        var isPlain: Bool { !isDefault && sheets.isEmpty && gate == nil }
        /// Whether a sheet's line says `over`: the sheets then stack, a launch puts up what each goes over, and in use
        /// one goes up over whatever is up.
        var isStacked: Bool { !over.isEmpty }
        /// Whether a sheet's line says `detents`: each sheet then goes up at its own heights, through
        /// `LayoutSheetDetents`, in place of the large detent alone.
        var hasDetents: Bool { !detents.isEmpty }
        /// The aliases of the gate's destination: a launch that names one holds the gate as the gate's own name does.
        var gateAliases: [String] { aliases.filter { $0.target == gate }.map(\.name) }
        /// Whether some destination is not a tab, so the tab bar and the sidebar list `AppDestination.tabs`.
        var hasNonTabs: Bool { !sheets.isEmpty || gate != nil }
        /// What the tab bar and the sidebar list.
        var listed: String { hasNonTabs ? "AppDestination.tabs" : "AppDestination.allCases" }
    }

    // MARK: - Destinations

    static func destinations(_ destinations: [Destination], split: Bool, aliases: [LaunchAlias] = []) -> String {
        let shape = Shape(destinations, aliases: aliases)
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
        if shape.aliases.isEmpty {
            code.line("/// The destination a launch asks for with `-destination <name>`: how UI tests and screenshots open a page.")
            code.scope("static var launchArgument: AppDestination? {") { code in
                code.line("UserDefaults.standard.string(forKey: \"destination\").flatMap(AppDestination.init(rawValue:))")
            }
            code.line()
        } else {
            launchNames(&code, shape)
        }
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
        if shape.isDrawn {
            drawnImages(&code, destinations)
        } else {
            code.line("/// The SF Symbol beside its name.")
            code.scope("var symbol: String {") { code in
                code.switchOn("self") { code in
                    for destination in destinations { code.line("case .\(SwiftName.member(destination.name)): \"\(destination.symbol)\"") }
                }
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

    /// A destination's image when a line draws a view in its symbol's place: its SF Symbol, or that view drawn once,
    /// at the screen's scale and in its own colours, so the tab bar never tints it.
    private static func drawnImages(_ code: inout Code, _ destinations: [Destination]) {
        let drawn = destinations.filter { $0.drawn != nil }.map { "`.\(SwiftName.member($0.name))`" }
        code.doc("The image beside its name: its SF Symbol, or for " + drawn.joined(separator: ", ")
                 + " a view the app has, drawn once at the screen's scale in its own colours, which the tab bar never tints.")
        code.scope("@MainActor func image(scale: CGFloat) -> Image {") { code in
            code.switchOn("self") { code in
                for destination in destinations {
                    let image = destination.drawn.map { "Self.drawn(\($0), scale: scale)" } ?? "Image(systemName: \"\(destination.symbol)\")"
                    code.line("case .\(SwiftName.member(destination.name)): \(image)")
                }
            }
        }
        code.line()
        code.line("/// `view` drawn into an image at `scale`, in its own colours.")
        code.scope("@MainActor private static func drawn(_ view: some View, scale: CGFloat) -> Image {") { code in
            code.line("let renderer = ImageRenderer(content: view)")
            code.line("renderer.scale = scale")
            code.line("#if os(iOS)")
            code.line("guard let image = renderer.uiImage else { return Image(systemName: \"circle.dashed\") }")
            code.line("return Image(uiImage: image).renderingMode(.original)")
            code.line("#else")
            code.line("guard let image = renderer.nsImage else { return Image(systemName: \"circle.dashed\") }")
            code.line("return Image(nsImage: image).renderingMode(.original)")
            code.line("#endif")
        }
    }

    /// How a tab bar item or a sidebar row shows a destination: its title beside its image, or with `tabBar: icons`
    /// an empty title, as `Tab("", …)` writes it.
    private static func label(_ shape: Shape, titled: Bool) -> String {
        let title = titled ? "destination.title" : "\"\""
        if shape.isDrawn { return "Label { Text(\(title)) } icon: { destination.image(scale: displayScale) }" }
        return "Label(\(title), systemImage: destination.symbol)"
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
        if shape.isDrawn { code.line("@Environment(\\.displayScale) private var displayScale") }
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
        if let feedback = shape.feedback, style == .adaptive || style == .tabs {
            code.line(".sensoryFeedback(\(feedback), trigger: layout.state.destination)")
        }
        overlays(&code, shape)
        if shape.isStacked {
            code.line(".modifier(LayoutSheetHost(level: 0))")
        } else if !shape.sheets.isEmpty {
            sheetHost(&code, mac: false, detents: shape.hasDetents)
        }
        code.close()
        if style == .adaptive || style == .tabs {
            code.line()
            code.scope("private var tabs: some View {") { code in
                code.scope("TabView(selection: layout.binding(\\.destination) { .destination($0) }) {") { code in
                    code.scope("ForEach(\(shape.listed)) { destination in") { code in
                        code.scope("NavigationStack {") { $0.line("destination.view") }
                        code.line(".tabItem { \(label(shape, titled: !shape.iconsOnly)) }")
                        code.line(".tag(destination)")
                    }
                }
                if let tint = shape.tint { code.line(".tint(\(tint))") }
            }
        }
        if style == .adaptive || style == .sidebar {
            code.line()
            code.scope("private var sidebar: some View {") { code in
                code.open("NavigationSplitView {")
                sidebarList(&code, title: appTitle, listed: shape.listed, label: label(shape, titled: true))
                code.middle("} detail: {")
                code.scope("NavigationStack {") { $0.line("layout.state.destination.view") }
                code.close()
            }
        }
        if style == .split {
            code.line()
            code.scope("private var columns: some View {") { code in
                code.open("NavigationSplitView {")
                sidebarList(&code, title: appTitle, listed: shape.listed, label: label(shape, titled: true))
                code.middle("} content: {")
                code.scope("NavigationStack {") { $0.line("layout.state.destination.view") }
                code.middle("} detail: {")
                code.line("layout.state.destination.detail")
                code.close()
            }
        }
        selection(&code)
        code.close()
        if shape.isStacked { stackedSheetHost(&code, mac: false, detents: shape.hasDetents) }
        if shape.hasDetents { sheetDetents(&code) }
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
        if shape.isDrawn { code.line("@Environment(\\.displayScale) private var displayScale") }
        code.line()
        code.open("var body: some View {")
        code.open("NavigationSplitView {")
        sidebarList(&code, title: appTitle, listed: shape.listed, label: label(shape, titled: true))
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
        overlays(&code, shape)
        if shape.isStacked {
            code.line(".modifier(LayoutSheetHost(level: 0))")
        } else if !shape.sheets.isEmpty {
            sheetHost(&code, mac: true, detents: shape.hasDetents)
        }
        code.close()
        selection(&code)
        code.close()
        if shape.isStacked { stackedSheetHost(&code, mac: true, detents: shape.hasDetents) }
        if shape.hasDetents { sheetDetents(&code) }
        code.line("#endif")
        return code.text
    }

    private static func sidebarList(_ code: inout Code, title: String, listed: String, label: String) {
        code.scope("List(\(listed), selection: sidebarSelection) { destination in") { code in
            code.line(label)
            code.line("    .tag(destination)")
        }
        code.line(".navigationTitle(\"\(SwiftName.escaped(title))\")")
        code.line(".navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 300)")
    }

    /// The views `overlays` names, over the tabs and under every sheet, bottom to top.
    private static func overlays(_ code: inout Code, _ shape: Shape) {
        for overlay in shape.overlays { code.line(".overlay { \(overlay) }") }
    }

    /// The sheet over the tabs, from LayoutService's `sheet`: the page in a stack of its own, at the large detent (with
    /// `detents`, at its own heights), closed by its button or a swipe down (the binding writes nil back), and on the Mac
    /// at a window's size.
    private static func sheetHost(_ code: inout Code, mac: Bool, detents: Bool) {
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
            heights(&code, detents: detents)
        }
    }

    /// A sheet's heights: the large detent alone, as before `detents`, or with `detents` the sheet's own.
    private static func heights(_ code: inout Code, detents: Bool) {
        code.line(detents ? ".modifier(LayoutSheetDetents(destination: destination))" : ".presentationDetents([.large])")
    }

    /// The heights a sheet rests at (a shape that says `detents`): the ones its line names, up at the first of them, a
    /// launch's sheets too, with the drag indicator showing; the large detent alone for a sheet whose line names none.
    private static func sheetDetents(_ code: inout Code) {
        code.line()
        code.doc("A sheet at the heights its line names: up at the first of them, on a launch too, with the drag indicator showing, "
                 + "then where the person drags it; a sheet whose line names none goes up large.")
        code.open("private struct LayoutSheetDetents: ViewModifier {")
        code.line("let destination: AppDestination")
        code.line("/// The height the sheet rests at: the first of its detents when it goes up.")
        code.line("@State private var detent: PresentationDetent")
        code.line()
        code.scope("init(destination: AppDestination) {") { code in
            code.line("self.destination = destination")
            code.line("_detent = State(initialValue: destination.detents.first ?? .large)")
        }
        code.line()
        code.scope("func body(content: Content) -> some View {") { code in
            code.line("content")
            code.indent()
            code.line(".presentationDetents(Swift.Set(destination.detents), selection: $detent)")
            code.line(".presentationDragIndicator(destination.dragIndicator)")
            code.dedent()
        }
        code.close()
    }

    /// The sheets LayoutService holds, one over another (a shape that says `over`): the one at `level` in a stack of
    /// its own with a close button, at the large detent (with `detents`, at its own heights), and over it the next. A
    /// launch's sheets go up at once and unanimated, each once the one under it is up, as if the person had gone there;
    /// in use one slides up over whatever is up, and a swipe down takes down it and every one over it.
    private static func stackedSheetHost(_ code: inout Code, mac: Bool, detents: Bool) {
        code.line()
        code.doc("The sheet at `level` of LayoutService's sheets, over the view: the page in a stack of its own with a close button, "
                 + "and over it the next. A launch's sheets go up at once, unanimated, each over the one under it, as if the person had "
                 + "gone there; in use one slides up over whatever is up.")
        code.open("private struct LayoutSheetHost: ViewModifier {")
        code.line("let level: Int")
        code.line("@Relay var layout: LayoutService")
        code.line("@StateObject private var clock = RelayClock([RelayClock.on(LayoutService.self)])")
        code.line("/// The sheet on screen at this level: LayoutService's, put up without animation the first time.")
        code.line("@State private var shown: AppDestination?")
        code.line()
        code.open("func body(content: Content) -> some View {")
        code.line("content")
        code.indent()
        code.scope(".sheet(item: $shown) { destination in") { code in
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
            code.line(".modifier(LayoutSheetHost(level: level + 1))")
            if mac { code.line(".frame(minWidth: Routes.windowSize.width, minHeight: Routes.windowSize.height)") }
            heights(&code, detents: detents)
        }
        code.scope(".task {") { code in
            code.line("// A launch's sheets: each goes up once the one under it is up, without animation.")
            code.line("guard shown == nil, let sheet else { return }")
            code.line("if level > 0 { try? await Task.sleep(for: .milliseconds(150)) }")
            code.line("var unanimated = Transaction()")
            code.line("unanimated.disablesAnimations = true")
            code.line("withTransaction(unanimated) { shown = sheet }")
        }
        code.scope(".onChange(of: layout.state.sheets) { _, _ in") { code in
            code.line("if shown != sheet { shown = sheet }")
        }
        code.scope(".onChange(of: shown) { _, now in") { code in
            code.line("// Swiped down: this sheet closes, and every one over it.")
            code.line("if now == nil, sheet != nil { layout.set(.sheets(Array(layout.state.sheets.prefix(level)))) }")
        }
        code.dedent()
        code.close()
        code.line()
        code.line("/// LayoutService's sheet at this level; nil when none is.")
        code.scope("private var sheet: AppDestination? {") { code in
            code.line("layout.state.sheets.indices.contains(level) ? layout.state.sheets[level] : nil")
        }
        code.close()
    }

    /// `launchArgument` read through the launch aliases, the aliases, every name a launch may give, and the destination
    /// a name opens: a shape with aliases writes these in place of the plain `launchArgument`.
    private static func launchNames(_ code: inout Code, _ shape: Shape) {
        code.line("/// The destination a launch asks for with `-destination <name>`: how UI tests and screenshots open a page. A name in")
        code.line("/// `aliases` opens the destination it names, and stays in the `destination` default for that page to read.")
        code.scope("static var launchArgument: AppDestination? {") { code in
            code.line("UserDefaults.standard.string(forKey: \"destination\").flatMap(AppDestination.init(launchName:))")
        }
        code.line()
        code.line("/// The other names a launch may give, each opening its destination exactly as the destination's own name does: the")
        code.line("/// page reads which with `UserDefaults.standard.string(forKey: \"destination\")` and opens its own inner state.")
        code.scope("static let aliases: [(name: String, destination: AppDestination)] = [", close: "]") { code in
            for alias in shape.aliases { code.line("(\"\(alias.name)\", .\(alias.target)),") }
        }
        code.line()
        code.line("/// Every name a launch may give, the destinations' own and then the aliases: what UI tests and screenshots open.")
        code.line("static var launchNames: [String] { allCases.map(\\.rawValue) + aliases.map(\\.name) }")
        code.line()
        code.line("/// The destination a launch name opens: the one of that name, or the one its alias names.")
        code.scope("init?(launchName: String) {") { code in
            code.scope("guard let destination = AppDestination(rawValue: launchName) ?? AppDestination.aliases.first(where: { $0.name == launchName })?.destination else {") { code in
                code.line("return nil")
            }
            code.line("self = destination")
        }
        code.line()
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
        if shape.isStacked {
            code.line("/// What a launch that names the sheet puts up under it: the tab it goes up over, selected first, or the sheet it")
            code.line("/// stacks on, put up first; nil for one that goes up over `.\(shape.opening)`. In use a sheet goes up over whatever is up.")
            code.scope("var over: AppDestination? {") { code in
                code.switchOn("self") { code in
                    for sheet in shape.sheets { if let under = shape.over[sheet] { code.line("case .\(sheet): .\(under)") } }
                    code.line("default: nil")
                }
            }
            code.line()
        }
        if shape.hasDetents {
            let named = shape.sheets.filter { shape.detents[$0] != nil }
            code.line("/// The heights it rests at as a sheet, the first where it goes up, on a launch too: as its line names them, else")
            code.line("/// the large detent alone.")
            code.scope("var detents: [PresentationDetent] {") { code in
                code.switchOn("self") { code in
                    for sheet in named { code.line("case .\(sheet): [" + (shape.detents[sheet] ?? []).map(\.swift).joined(separator: ", ") + "]") }
                    code.line("default: [.large]")
                }
            }
            code.line()
            code.line("/// Whether its sheet shows the drag indicator: one whose line names its heights does.")
            code.scope("var dragIndicator: Visibility {") { code in
                code.switchOn("self") { code in
                    code.line("case " + named.map { ".\($0)" }.joined(separator: ", ") + ": .visible")
                    code.line("default: .automatic")
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
            if let alias = shape.gateAliases.first {
                code.line("/// An alias opens what its destination opens: `-destination \(alias)` holds the gate as `-destination \(gate)` does.")
            } else if let alias = shape.aliases.first {
                code.line("/// An alias opens what its destination opens: `-destination \(alias.name)` opens past the gate as `-destination \(alias.target)` does.")
            }
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
