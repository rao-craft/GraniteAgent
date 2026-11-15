//  WHAT: The root page: it boots the app once the settings have loaded, shows a spinner while it starts, the reason
//        and a retry when it failed, and the app when it is ready; it applies the appearance and hosts the modals.
//        Four readies: a first screen (a new project), the view the app had before (a linked project), the app's
//        navigation (after `make: navigation`), and that navigation behind a gate (`AppGate`, written in the root's
//        own view file so a navigation made again without a gate leaves nothing of it behind).

import Foundation

enum RootTemplates {
    enum Ready {
        /// A new app's first screen: its name.
        case welcome(String)
        /// The view the app had before Granite, passed in.
        case content
        /// The app's destinations.
        case navigation
        /// The app's destinations behind a gate.
        case gated(Gate)
    }

    /// What holds the app behind its gate: the destination shown while it holds, and the condition over the relays.
    struct Gate: Equatable, Sendable {
        /// The gate's case of `AppDestination` and its title.
        var name: String
        var title: String
        /// A tab a launch may name to open past the gate, for the comment: `seer`.
        var tab: String
        /// The Swift condition that holds the gate, and the relays it reads.
        var condition: String
        var relays: [Relay]
    }

    static func component(_ root: String, hostsContent: Bool) -> String {
        var text = """
            import Granite
            import SwiftUI

            /// The app's root page: it boots the app once the settings have loaded, and shows the app when it is ready.
            struct \(root): GraniteComponent {
                @Command var center: Center

                @Relay var environment: EnvironmentService
                @Relay var config: ConfigService
            """
        if hostsContent {
            text += """


                    /// What the app shows once it is ready: the view it had before Granite.
                    let content: () -> AnyView

                    init<Content: View>(@ViewBuilder content: @escaping () -> Content) {
                        self.content = { AnyView(content()) }
                    }
                """
        }
        return text + "\n}\n"
    }

    static func center(_ root: String) -> String {
        """
        import Granite

        extension \(root) {
            struct Center: GraniteCenter {
                struct State: GraniteState {}

                @Store var state: State
            }
        }

        """
    }

    static func view(_ root: String, ready: Ready) -> String {
        let readyView: String
        switch ready {
        case .welcome(let name):
            readyView = """
                                NavigationStack {
                                    ContentUnavailableView("\(SwiftName.escaped(name))", systemImage: "square.grid.2x2", description: Text("Everything is in place."))
                                }
                """
        case .content:
            readyView = "                content()"
        case .navigation:
            readyView = "                PlatformNavigationView()"
        case .gated:
            readyView = "                AppGate()"
        }
        var gate = ""
        if case .gated(let held) = ready { gate = "\n" + Self.gate(held) }
        return """
            import Granite
            import SwiftUI

            extension \(root): View {
                var view: some View {
                    Group {
                        switch environment.state.phase {
                        case .idle:
                            ProgressView("Starting…")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .ready:
            \(readyView)
                        case .failed:
                            ContentUnavailableView {
                                Label("Couldn’t Start", systemImage: "exclamationmark.triangle")
                            } description: {
                                Text(environment.state.lastError ?? String(localized: "Something went wrong while starting."))
                            } actions: {
                                Button("Try Again") {
                                    Task { await AppRoot.shared.boot() }
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    .preferredColorScheme(config.state.appearance.colorScheme)
                    .modalHosted()
                    .task(id: config.isLoaded) {
                        guard config.isLoaded else { return }
                        await AppRoot.shared.boot()
                    }
                }
            }

            """ + gate
    }

    /// The gate before the app's destinations: the gate's page full screen while its condition holds, the navigation
    /// once it stops, and a launch that names another destination past it.
    static func gate(_ gate: Gate) -> String {
        var code = Code()
        code.doc("The gate before the app: \(gate.title) full screen while `\(gate.condition)` holds, and the app's destinations once it stops holding.")
        code.line("///")
        code.line("/// A launch that names any destination but the gate's own (`-destination \(gate.tab)`) opens past the gate, on that")
        code.line("/// destination: how UI tests and screenshots check each screen with no sign-in and no tap. With no `-destination`, or")
        code.line("/// `-destination \(gate.name)`, the gate holds by its condition.")
        code.open("struct AppGate: View {")
        for relay in gate.relays { code.line("@Relay var \(relay.name): \(relay.type)") }
        code.line("@StateObject private var clock = RelayClock([" + gate.relays.map { "RelayClock.on(\($0.type).self)" }.joined(separator: ", ") + "])")
        code.line()
        code.open("var body: some View {")
        code.open("if holds {")
        code.scope("NavigationStack {") { $0.line("AppDestination.gate.view") }
        code.line("#if os(macOS)")
        code.line(".frame(minWidth: LayoutService.minimumWidth, minHeight: LayoutService.minimumHeight)")
        code.line("#endif")
        code.middle("} else {")
        code.line("PlatformNavigationView()")
        code.close()
        code.close()
        code.line()
        code.line("/// Whether the gate holds: its condition, unless the launch named another destination to open past it.")
        code.scope("private var holds: Bool {") { code in
            code.line("if AppDestination.opensPastGate(AppDestination.launchArgument) { return false }")
            code.line("return \(gate.condition)")
        }
        code.close()
        return code.text
    }
}
