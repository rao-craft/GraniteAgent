//  WHAT: The layout service (where the app is), the routes over Granite's router, and Device: the files
//        `make: navigation` writes beside the navigation views. A `Shape` that says a default, sheets or a gate adds
//        to them (the tab a plain launch opens on, the sheet over the tabs, the launch rule past the gate); a plain
//        one writes them as they were.

import Foundation

extension NavigationTemplates {
    /// The layout service's files, by their path inside its folder.
    static func layoutService(app: String, first: String, shape: Shape? = nil) -> [(path: String, text: String)] {
        guard let shape, !shape.isPlain else {
            return [("LayoutService.swift", layout),
                    ("LayoutService+Center.swift", layoutCenter(app: app, first: first)),
                    ("Reducers/LayoutService.Set.swift", layoutSet),
                    ("Ops/LayoutOps.swift", layoutOps),
                    ("Models/LayoutStyle.swift", layoutStyle)]
        }
        return [("LayoutService.swift", layout(shape)),
                ("LayoutService+Center.swift", layoutCenter(app: app, shape: shape)),
                ("Reducers/LayoutService.Set.swift", layoutSet(shape)),
                ("Ops/LayoutOps.swift", layoutOps(shape)),
                ("Models/LayoutStyle.swift", layoutStyle)]
    }

    /// LayoutService with what the shape adds: `select` that knows the sheets and the gate, `present` and
    /// `closeSheet`.
    static func layout(_ shape: Shape) -> String {
        var text = layout
        let select = "    /// Goes to `destination`.\n"
        if let sheet = shape.sheets.first {
            text = text.replacingOccurrences(of: select, with: "    /// Goes to `destination`: a tab is selected and any sheet closes; a sheet goes up over the tab on screen"
                                             + (shape.gate == nil ? ".\n" : ";\n    /// the gate is shown while it holds, never gone to.\n"))
            let closeDetail = """
                    /// Closes the detail pane.
                    func closeDetail() {
                        set(.detail(nil))
                    }

                """
            text = text.replacingOccurrences(of: closeDetail, with: closeDetail + """

                    /// Puts `destination` up in a sheet over the tabs: `layout.present(.\(sheet))`.
                    func present(_ destination: AppDestination) {
                        set(.sheet(destination))
                    }

                    /// Closes the sheet over the tabs.
                    func closeSheet() {
                        set(.sheet(nil))
                    }

                """)
        } else if shape.gate != nil {
            text = text.replacingOccurrences(of: select, with: "    /// Goes to `destination`, a tab; the gate is shown while it holds, never gone to.\n")
        }
        return text
    }

    /// The center when the shape says a default, sheets or a gate: the state starts where the launch asks
    /// (`init(launch:)`, what the tests read), a sheet sits beside the tab, and with a default nothing is kept between
    /// launches, so a plain launch always opens on it.
    static func layoutCenter(app: String, shape: Shape) -> String {
        let opening = shape.opening
        var code = Code()
        code.block("""
            import Foundation
            import Granite
            import GraniteAgents

            extension LayoutService {
            """)
        code.indent()
        code.open("struct Center: GraniteCenter {")
        code.open("struct State: GraniteState {")
        code.line("/// The tab on screen: the one a launch asks for (`-destination <name>`), else `.\(opening)`"
                  + (shape.isDefault ? ", the default." : ", the first."))
        code.line("var destination: AppDestination")
        if let sheet = shape.sheets.first {
            code.line("/// The sheet up over the tabs, nil when none is: `layout.present(.\(sheet))`.")
            code.line("var sheet: AppDestination?")
        }
        code.line("/// Whether the window is compact (a tab bar) or expanded (a sidebar beside the page).")
        code.line("var style: LayoutStyle = .compact")
        code.line("/// What the detail pane shows, by id; nil when it is closed.")
        code.line("var detail: String?")
        code.line()
        code.scope("init() {") { $0.line("self.init(launch: AppDestination.launchArgument)") }
        code.line()
        var opens = ["on that tab"]
        if !shape.sheets.isEmpty { opens.append("on `.\(opening)` with the sheet up over it when it names a sheet") }
        if shape.gate != nil { opens.append("on `.\(opening)`, behind the gate, when it names the gate") }
        opens.append("on `.\(opening)` when it names nothing")
        code.doc("Where a launch that asks for `launch` (`-destination <name>`) opens: " + opens.joined(separator: "; ") + ".")
        code.scope("init(launch: AppDestination?) {") { code in
            code.line(shape.hasNonTabs ? "destination = launch.flatMap { $0.isTab ? $0 : nil } ?? .\(opening)" : "destination = launch ?? .\(opening)")
            if !shape.sheets.isEmpty { code.line("sheet = launch.flatMap { $0.isSheet ? $0 : nil }") }
        }
        if !shape.isDefault {
            code.line()
            code.scope("enum CodingKeys: String, CodingKey {") { $0.line("case destination") }
            code.line()
            code.line("/// Only the tab on screen is kept between launches; one the app no longer has, or no longer lists as a tab,")
            code.line("/// reads as the first, and a destination a launch asks for wins over both.")
            code.scope("init(from decoder: Decoder) throws {") { code in
                code.line("let container = try decoder.container(keyedBy: CodingKeys.self)")
                code.line("self.init(launch: AppDestination.launchArgument)")
                code.scope("if AppDestination.launchArgument == nil, let stored = try? container.decodeIfPresent(AppDestination.self, forKey: .destination), stored.isTab {") { code in
                    code.line("destination = stored")
                }
            }
        }
        code.close()
        code.line()
        code.line("@Event var set: Set.Reducer")
        code.line()
        if shape.isDefault {
            code.line("/// Nothing of where the app was is kept between launches: a plain launch opens on `.\(opening)`, the default.")
            code.line("@Store var state: State")
        } else {
            code.line("@Store(persist: \"persistence.\(app).layout.0001\", autoSave: true, preload: true) var state: State")
        }
        code.line()
        code.line("init() {}")
        code.close()
        code.dedent()
        code.line("}")
        return code.text
    }

    /// The writer with a kind for the sheet.
    static func layoutSet(_ shape: Shape) -> String {
        guard !shape.sheets.isEmpty else { return layoutSet }
        return layoutSet.replacingOccurrences(of: "                case detail(String?)\n",
                                              with: "                case detail(String?)\n                case sheet(AppDestination?)\n")
    }

    /// Ops that put a sheet up over the tab on screen, and never go to the gate.
    static func layoutOps(_ shape: Shape) -> String {
        guard shape.hasNonTabs else { return layoutOps }
        let destination = """
                    case .destination(let destination):
                        state.destination = destination
                        state.detail = nil

            """
        let routed: String
        if shape.sheets.isEmpty {
            routed = """
                        case .destination(let destination):
                            // The gate is shown while it holds, never gone to.
                            guard destination.isTab else { return }
                            state.destination = destination
                            state.detail = nil

                """
        } else {
            routed = """
                        case .destination(let destination):
                            if destination.isSheet {
                                // A sheet goes up over the tab on screen, never in its place.
                                state.sheet = destination
                            } else if destination.isTab {
                \(shape.gate == nil ? "" : "                // The gate is shown while it holds, never gone to: only a tab is.\n")                state.destination = destination
                                state.detail = nil
                                state.sheet = nil
                            }

                """
        }
        var text = layoutOps.replacingOccurrences(of: destination, with: routed)
        if !shape.sheets.isEmpty {
            text = text.replacingOccurrences(of: "        case .clear:\n", with: "        case .sheet(let destination):\n            state.sheet = destination\n        case .clear:\n")
        }
        return text
    }

    static let layout = """
        import Foundation
        import Granite
        import GraniteAgents
        import SwiftUI
        #if os(macOS)
        import AppKit
        #endif

        /// Where the app is: the destination on screen, whether the window is compact or expanded, and what the detail
        /// pane shows. Pages, menus and the root move the app through it.
        struct LayoutService: GraniteService {
            @Service(.online) var center: Center

            init() {}

            /// The Mac window's width with the detail pane closed, and open.
            static let compactWidth: CGFloat = 720
            static let expandedWidth: CGFloat = 1200
            /// The least the Mac window may be.
            static let minimumWidth: CGFloat = 640
            static let minimumHeight: CGFloat = 480
        }

        extension LayoutService: @unchecked Sendable {}

        extension LayoutService {
            /// Changes where the app is through its one writer, on main.
            func set(_ kind: Set.Meta.Kind) {
                let service = self
                onMain { service.center.set.send(Set.Meta(kind: kind)) }
            }

            /// A binding to a field of the layout, written through `set`: `layout.binding(\\.destination) { .destination($0) }`.
            func binding<Value>(_ keyPath: KeyPath<Center.State, Value>, _ kind: @escaping (Value) -> Set.Meta.Kind) -> Binding<Value> {
                Binding(get: { self.state[keyPath: keyPath] }, set: { self.set(kind($0)) })
            }

            /// Goes to `destination`.
            func select(_ destination: AppDestination) {
                set(.destination(destination))
            }

            /// Shows `id` in the detail pane.
            func show(detail id: String) {
                set(.detail(id))
            }

            /// Closes the detail pane.
            func closeDetail() {
                set(.detail(nil))
            }

            #if os(macOS)
            /// Sets the key window's width, keeping its left edge, in a hop to main: AppKit is main-only.
            static func resizeWindow(width: CGFloat) {
                Task { @MainActor in
                    guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.windows.first else { return }
                    var frame = window.frame
                    frame.size.width = max(width, window.minSize.width)
                    window.setFrame(frame, display: true, animate: true)
                }
            }
            #endif
        }

        """

    static func layoutCenter(app: String, first: String) -> String {
        """
        import Foundation
        import Granite
        import GraniteAgents

        extension LayoutService {
            struct Center: GraniteCenter {
                struct State: GraniteState {
                    /// The destination on screen: the one a launch asks for (`-destination search`), else the first.
                    var destination: AppDestination = AppDestination.launchArgument ?? .\(first)
                    /// Whether the window is compact (a tab bar) or expanded (a sidebar beside the page).
                    var style: LayoutStyle = .compact
                    /// What the detail pane shows, by id; nil when it is closed.
                    var detail: String?

                    init() {}

                    enum CodingKeys: String, CodingKey {
                        case destination
                    }

                    /// Only the destination is kept between launches; one the app no longer has reads as the first, and
                    /// one a launch asks for wins over both.
                    init(from decoder: Decoder) throws {
                        let container = try decoder.container(keyedBy: CodingKeys.self)
                        destination = AppDestination.launchArgument
                            ?? (try? container.decodeIfPresent(AppDestination.self, forKey: .destination)) ?? .\(first)
                    }
                }

                @Event var set: Set.Reducer

                @Store(persist: "persistence.\(app).layout.0001", autoSave: true, preload: true) var state: State

                init() {}
            }
        }

        """
    }

    static let layoutSet = """
        import Foundation
        import Granite

        extension LayoutService {
            /// The layout's one writer: every change is a kind, applied by `LayoutOps.apply` in the turn it is sent.
            struct Set: GraniteReducer {
                typealias Center = LayoutService.Center
                init() {}

                struct Meta: GranitePayload {
                    enum Kind: Sendable {
                        case destination(AppDestination)
                        case style(LayoutStyle)
                        case detail(String?)
                        case clear
                    }

                    var kind: Kind

                    init(kind: Kind) { self.kind = kind }
                }

                @Payload var meta: Meta?

                func reduce(state: inout Center.State) {
                    guard let meta else { return }
                    LayoutOps.apply(meta.kind, to: &state)
                }

                var thread: DispatchQueue? { nil }
            }
        }

        """

    static let layoutOps = """
        import Foundation

        /// Every change to where the app is, as one function a test can run without a relay.
        enum LayoutOps {
            static func apply(_ kind: LayoutService.Set.Meta.Kind, to state: inout LayoutService.Center.State) {
                switch kind {
                case .destination(let destination):
                    state.destination = destination
                    state.detail = nil
                case .style(let style):
                    state.style = style
                case .detail(let id):
                    state.detail = id
                case .clear:
                    state = .init()
                }
            }
        }

        """

    static let layoutStyle = """
        import Foundation

        /// How much room the window has.
        enum LayoutStyle: String, Codable, Sendable {
            /// One column: a tab bar, and pages pushed.
            case compact
            /// A sidebar beside the page, and room for a detail pane.
            case expanded
        }

        """

    static func layoutTests(module: String, first: String, second: String, shape: Shape? = nil) -> String {
        guard let shape, !shape.isPlain else { return plainLayoutTests(module: module, first: first, second: second) }
        let opening = shape.opening
        var code = Code()
        code.block("""
            import Foundation
            import Testing
            @testable import \(module)

            /// Where the app is, one test a change: what LayoutService's writer does, run without a relay, and where a
            /// launch opens.
            struct LayoutOpsTests {
                @Test func goingSomewhereClosesTheDetail() {
                    var state = LayoutService.Center.State()
                    LayoutOps.apply(.detail("item-1"), to: &state)
                    LayoutOps.apply(.destination(.\(second)), to: &state)
                    #expect(state.destination == .\(second))
                    #expect(state.detail == nil)
                }

                @Test func theStyleIsWritten() {
                    var state = LayoutService.Center.State()
                    LayoutOps.apply(.style(.expanded), to: &state)
                    #expect(state.style == .expanded)
                }

                @Test func theDetailOpensAndCloses() {
                    var state = LayoutService.Center.State()
                    LayoutOps.apply(.detail("item-1"), to: &state)
                    #expect(state.detail == "item-1")
                    LayoutOps.apply(.detail(nil), to: &state)
                    #expect(state.detail == nil)
                }

                @Test func clearStartsOver() {
                    var state = LayoutService.Center.State()
                    LayoutOps.apply(.destination(.\(second)), to: &state)
                    LayoutOps.apply(.clear, to: &state)
                    #expect(state == LayoutService.Center.State())
                }
            """)
        code.indent()
        if shape.isDefault {
            code.line()
            code.scope("@Test func aPlainLaunchOpensOnTheDefault() {") { code in
                code.line("#expect(LayoutService.Center.State(launch: nil).destination == .\(opening))")
                code.line("#expect(LayoutService.Center.State(launch: .\(second)).destination == .\(second))")
            }
        } else {
            code.line()
            code.scope("@Test func aDestinationTheAppNoLongerHasReadsAsTheFirst() throws {") { code in
                code.line("let stored = try PropertyListEncoder().encode([\"destination\": \"a-place-long-gone\"])")
                code.line("let state = try PropertyListDecoder().decode(LayoutService.Center.State.self, from: stored)")
                code.line("#expect(state.destination == .\(opening))")
            }
        }
        if let sheet = shape.sheets.first {
            code.line()
            code.scope("@Test func aSheetGoesUpOverTheTabAndCloses() {") { code in
                code.line("var state = LayoutService.Center.State(launch: nil)")
                code.line("LayoutOps.apply(.sheet(.\(sheet)), to: &state)")
                code.line("#expect(state.sheet == .\(sheet))")
                code.line("#expect(state.destination == .\(opening), \"the tab stays under it\")")
                code.line("LayoutOps.apply(.sheet(nil), to: &state)")
                code.line("#expect(state.sheet == nil)")
            }
            code.line()
            code.scope("@Test func aSheetIsNotATab() {") { code in
                code.line("#expect(!AppDestination.tabs.contains(.\(sheet)))")
                code.line("var state = LayoutService.Center.State(launch: nil)")
                code.line("LayoutOps.apply(.destination(.\(sheet)), to: &state)")
                code.line("#expect(state.sheet == .\(sheet), \"going to a sheet puts it up\")")
                code.line("#expect(state.destination == .\(opening), \"over the tab on screen\")")
                code.line("LayoutOps.apply(.destination(.\(second)), to: &state)")
                code.line("#expect(state.sheet == nil, \"going to a tab closes it\")")
            }
            code.line()
            code.scope("@Test func aLaunchThatAsksForASheetOpensItOverTheDefaultTab() {") { code in
                code.line("let state = LayoutService.Center.State(launch: .\(sheet))")
                code.line("#expect(state.destination == .\(opening))")
                code.line("#expect(state.sheet == .\(sheet))")
            }
        }
        if let gate = shape.gate {
            code.line()
            code.scope("@Test func theGateHoldsOnAPlainLaunchAndOnItsOwnName() {") { code in
                code.line("#expect(!AppDestination.opensPastGate(nil))")
                code.line("#expect(!AppDestination.opensPastGate(.\(gate)))")
                code.line("#expect(!AppDestination.tabs.contains(.\(gate)))")
                code.line("#expect(LayoutService.Center.State(launch: .\(gate)).destination == .\(opening), \"the tabs behind it\")")
            }
            code.line()
            code.scope("@Test func aLaunchThatNamesAnotherDestinationOpensPastTheGate() {") { code in
                code.scope("for destination in AppDestination.allCases where destination != .\(gate) {") { code in
                    code.line("#expect(AppDestination.opensPastGate(destination), \"-destination \\(destination.rawValue)\")")
                }
            }
            code.line()
            code.scope("@Test func theGateIsNeverGoneTo() {") { code in
                code.line("var state = LayoutService.Center.State(launch: nil)")
                code.line("LayoutOps.apply(.destination(.\(gate)), to: &state)")
                code.line("#expect(state.destination == .\(opening))")
            }
        }
        code.dedent()
        code.line("}")
        return code.text
    }

    private static func plainLayoutTests(module: String, first: String, second: String) -> String {
        """
        import Foundation
        import Testing
        @testable import \(module)

        /// Where the app is, one test a change: what LayoutService's writer does, run without a relay.
        struct LayoutOpsTests {
            @Test func goingSomewhereClosesTheDetail() {
                var state = LayoutService.Center.State()
                LayoutOps.apply(.detail("item-1"), to: &state)
                LayoutOps.apply(.destination(.\(second)), to: &state)
                #expect(state.destination == .\(second))
                #expect(state.detail == nil)
            }

            @Test func theStyleIsWritten() {
                var state = LayoutService.Center.State()
                LayoutOps.apply(.style(.expanded), to: &state)
                #expect(state.style == .expanded)
            }

            @Test func theDetailOpensAndCloses() {
                var state = LayoutService.Center.State()
                LayoutOps.apply(.detail("item-1"), to: &state)
                #expect(state.detail == "item-1")
                LayoutOps.apply(.detail(nil), to: &state)
                #expect(state.detail == nil)
            }

            @Test func clearStartsOver() {
                var state = LayoutService.Center.State()
                LayoutOps.apply(.destination(.\(second)), to: &state)
                LayoutOps.apply(.clear, to: &state)
                #expect(state == LayoutService.Center.State())
            }

            @Test func aDestinationTheAppNoLongerHasReadsAsTheFirst() throws {
                let stored = try PropertyListEncoder().encode(["destination": "a-place-long-gone"])
                let state = try PropertyListDecoder().decode(LayoutService.Center.State.self, from: stored)
                #expect(state.destination == .\(first))
            }
        }

        """
    }

    static let routes = """
        //  Where a page goes next, over Granite's router: pushed onto the navigation stack it sits in, or on the Mac
        //  opened in a window of its own. The app keeps SwiftUI's stacks for pushes, so its bars and titles stay the
        //  system's; Granite's router opens the Mac's windows and pushes onto a stack `.graniteNavigation` made.

        import Granite
        import SwiftUI

        extension View {
            /// Opens `destination` when tapped: in a window of its own on the Mac, pushed onto the stack elsewhere.
            func routes<Destination: View>(title: String = "", window size: CGSize = Routes.windowSize,
                                           @ViewBuilder to destination: @escaping () -> Destination) -> some View {
                modifier(RouteModifier(title: title, size: size, destination: destination))
            }
        }

        /// Pushes and windows, called from a view's action or the root; navigation is main-only.
        enum Routes {
            /// A window's size when a route names none.
            static let windowSize = CGSize(width: 480, height: 640)

            /// Pushes `destination` onto the stack `router` drives: one `.graniteNavigation` made.
            @MainActor
            static func push<Destination: View>(_ router: GraniteNavigation.Router, @ViewBuilder _ destination: @escaping () -> Destination) {
                router.push(destination)
            }

            #if os(macOS)
            /// Opens `destination` in a window of its own, or brings forward the one already open under `id`.
            @MainActor
            static func window<Destination: View>(id: String, title: String, size: CGSize = windowSize,
                                                  @ViewBuilder _ destination: @escaping () -> Destination) {
                GraniteNavigationWindow.shared.addWindow(id: id, props: GraniteRouteWindowProperties(title: title, style: .init(size: size, mask: .resizable))) {
                    destination()
                }
            }
            #endif
        }

        /// A tap that opens a destination: Granite's window route on the Mac, a navigation link elsewhere.
        private struct RouteModifier<Destination: View>: ViewModifier {
            @Environment(\\.graniteRouter) private var router
            let title: String
            let size: CGSize
            let destination: () -> Destination

            func body(content: Content) -> some View {
                #if os(macOS)
                content.route(title: title, window: GraniteRouteWindowProperties(title: title, style: .init(size: size, mask: .resizable)),
                              component: destination, with: { router })
                #else
                NavigationLink {
                    destination()
                } label: {
                    content
                }
                #endif
            }
        }

        """

    static let device = """
        import SwiftUI
        #if os(iOS)
        import UIKit
        #endif

        /// What the app runs on: the platform, the idiom, and the version people see.
        enum Device {
            /// Whether the app runs on a Mac.
            static var isMacOS: Bool {
                #if os(macOS)
                return true
                #else
                return false
                #endif
            }

            /// Whether the app runs on an iPad.
            @MainActor static var isiPad: Bool {
                #if os(iOS)
                return UIDevice.current.userInterfaceIdiom == .pad
                #else
                return false
                #endif
            }

            /// Whether the app runs on an iPhone.
            @MainActor static var isiPhone: Bool {
                #if os(iOS)
                return UIDevice.current.userInterfaceIdiom == .phone
                #else
                return false
                #endif
            }

            /// Whether the window has room for a sidebar beside the page: a Mac or an iPad.
            @MainActor static var isExpandedLayout: Bool { isMacOS || isiPad }

            /// The version people see, as "1.0 (1)".
            static var appVersion: String {
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
                return "\\(version) (\\(build))"
            }
        }

        """
}
