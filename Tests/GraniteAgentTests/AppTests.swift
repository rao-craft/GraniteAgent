import Foundation
import XCTest
@testable import GraniteAgent

/// The makes that shape the whole app: its navigation, its modals, a kit beside it, and Granite brought into a
/// project this package did not make.
final class AppTests: XCTestCase {
    private func app(pages: Bool = true) async throws -> URL {
        let folder = try Fixture.folder()
        try await Fixture.call(Fixture.project, in: folder)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Shared/Models"), withIntermediateDirectories: true)
        try Fixture.recipe.write(to: folder.appendingPathComponent("Shared/Models/Recipe.swift"), atomically: true, encoding: .utf8)
        try await Fixture.call(Fixture.recipesService, in: folder)
        if pages {
            for page in [Fixture.recipeList, Fixture.search, Fixture.settings] { try await Fixture.call(page, in: folder) }
        }
        return folder
    }

    private func read(_ folder: URL, _ path: String) throws -> String {
        try String(contentsOf: folder.appendingPathComponent(path), encoding: .utf8)
    }

    func testNavigationShowsTheDestinationsOnceTheAppIsReady() async throws {
        let folder = try await app()
        let result = try await Fixture.call(Fixture.navigation, in: folder)
        let written = Set(result.paths.map { String($0.dropFirst(folder.path.count + 1)) })
        for path in ["Shared/Utility/AppDestination.swift", "iOS/PlatformNavigationView.swift", "macOS/PlatformNavigationView.swift", "Shared/Utility/Routes.swift",
                     "Shared/Utility/Device.swift", "Services/LayoutService/LayoutService.swift", "Services/LayoutService/LayoutService+Center.swift",
                     "Services/LayoutService/Reducers/LayoutService.Set.swift", "Services/LayoutService/Ops/LayoutOps.swift",
                     "Services/LayoutService/Models/LayoutStyle.swift", "Components/Home/Home+View.swift", "Tests/LayoutOpsTests.swift", "Shared/Utility/AppRoot.swift"] {
            XCTAssertTrue(written.contains(path), path)
        }
        let destinations = try read(folder, "Shared/Utility/AppDestination.swift")
        XCTAssertTrue(destinations.contains("static var launchArgument: AppDestination? {"), "a launch picks its page: -destination <name>")
        XCTAssertTrue(try read(folder, "Services/LayoutService/LayoutService+Center.swift").contains("AppDestination.launchArgument ?? ."), "and wins over the default")
        XCTAssertTrue(destinations.contains("case recipes\n    case search\n    case settings"))
        XCTAssertTrue(destinations.contains("case .recipes: String(localized: \"Recipes\")"))
        XCTAssertTrue(destinations.contains("case .search: RecipeSearch()"))
        let iOS = try read(folder, "iOS/PlatformNavigationView.swift")
        XCTAssertTrue(iOS.hasPrefix("#if os(iOS)") && iOS.contains("if horizontalSizeClass == .compact {\n                tabs"))
        XCTAssertTrue(iOS.contains("TabView(selection: layout.binding(\\.destination) { .destination($0) }) {"))
        let macOS = try read(folder, "macOS/PlatformNavigationView.swift")
        XCTAssertTrue(macOS.contains(".frame(minWidth: LayoutService.minimumWidth, minHeight: LayoutService.minimumHeight)"))
        XCTAssertTrue(try read(folder, "Services/LayoutService/LayoutService+Center.swift").contains("var destination: AppDestination = AppDestination.launchArgument ?? .recipes"))
        let home = try read(folder, "Components/Home/Home+View.swift")
        XCTAssertTrue(home.contains("case .ready:\n                PlatformNavigationView()"))
        XCTAssertTrue(home.contains("AppRoot.shared.boot()"), "the boot gating stays")
        XCTAssertTrue(try read(folder, "Shared/Utility/AppRoot.swift").contains("@Relay(.silence) var layout: LayoutService"))
        XCTAssertTrue(try read(folder, "Shared/Utility/Routes.swift").contains("GraniteNavigationWindow.shared.addWindow(id: id"))
        for (path, added) in [("Shared/Utility/AppDestination.swift", "static var tabs"), ("iOS/PlatformNavigationView.swift", ".sheet(item:"),
                              ("Services/LayoutService/LayoutService.swift", "func present("), ("Components/Home/Home+View.swift", "AppGate")] {
            XCTAssertFalse(try read(folder, path).contains(added), "a call with no default, sheet or gate writes what it wrote before them: \(path)")
        }
    }

    /// Seer's shell (2026-11-15): Sign In full screen until there is a session, three tabs with the middle one where a
    /// plain launch opens, the other places sheets over them, and every place reachable from `-destination <name>`.
    func testADefaultSheetsAndAGateShapeTheNavigation() async throws {
        let folder = try Fixture.folder()
        try await Fixture.call(Fixture.seerProject, in: folder)
        try await Fixture.call(Fixture.account, in: folder)
        try await Fixture.call(Fixture.signIn, in: folder)
        for page in Fixture.seerPages { try await Fixture.call(page, in: folder) }
        let result = try await Fixture.call(Fixture.seerNavigation, in: folder)
        XCTAssertEqual(result.expected.map(\.name), ["auth", "library", "seer", "models", "profile", "wallet"])
        XCTAssertTrue(result.notes.contains { $0.contains("a plain launch opens on `seer`") }, "\(result.notes)")

        let destinations = try read(folder, "Shared/Utility/AppDestination.swift")
        for line in ["case .auth, .profile, .wallet: false", "static var tabs: [AppDestination] { allCases.filter(\\.isTab) }",
                     "case .profile, .wallet: true", "static let gate: AppDestination = .auth",
                     "static func opensPastGate(_ destination: AppDestination?) -> Bool {", "return destination != gate", "case .wallet: Wallet()"] {
            XCTAssertTrue(destinations.contains(line), line)
        }
        let center = try read(folder, "Services/LayoutService/LayoutService+Center.swift")
        XCTAssertTrue(center.contains("destination = launch.flatMap { $0.isTab ? $0 : nil } ?? .seer"), "a plain launch, or the gate's name, opens on the default")
        XCTAssertTrue(center.contains("sheet = launch.flatMap { $0.isSheet ? $0 : nil }"), "-destination wallet opens the default with Wallet up")
        XCTAssertTrue(center.contains("@Store var state: State"), "with a default, nothing of where the app was is kept")
        let service = try read(folder, "Services/LayoutService/LayoutService.swift")
        XCTAssertTrue(service.contains("func present(_ destination: AppDestination) {\n        set(.sheet(destination))") && service.contains("func closeSheet() {"))
        XCTAssertTrue(try read(folder, "Services/LayoutService/Reducers/LayoutService.Set.swift").contains("case sheet(AppDestination?)"))
        XCTAssertTrue(try read(folder, "Services/LayoutService/Ops/LayoutOps.swift").contains("if destination.isSheet {\n                // A sheet goes up over the tab on screen"))
        for platform in ["iOS", "macOS"] {
            let view = try read(folder, "\(platform)/PlatformNavigationView.swift")
            for line in ["List(AppDestination.tabs, selection: sidebarSelection)", ".sheet(item: layout.binding(\\.sheet) { .sheet($0) }) { destination in",
                         "Button(\"Close\", systemImage: \"xmark\") { layout.closeSheet() }", ".presentationDetents([.large])"] {
                XCTAssertTrue(view.contains(line), "\(platform): \(line)")
            }
        }
        XCTAssertTrue(try read(folder, "iOS/PlatformNavigationView.swift").contains("ForEach(AppDestination.tabs) { destination in"))
        let home = try read(folder, "Components/Home/Home+View.swift")
        for line in ["case .ready:\n                AppGate()", "struct AppGate: View {", "@Relay var account: AccountService",
                     "if AppDestination.opensPastGate(AppDestination.launchArgument) { return false }", "return account.state.session == nil",
                     "AppDestination.gate.view", "opens past the gate"] {
            XCTAssertTrue(home.contains(line), line)
        }
        let tests = try read(folder, "Tests/LayoutOpsTests.swift")
        for test in ["aPlainLaunchOpensOnTheDefault", "aSheetGoesUpOverTheTabAndCloses", "aSheetIsNotATab", "aLaunchThatAsksForASheetOpensItOverTheDefaultTab",
                     "theGateHoldsOnAPlainLaunchAndOnItsOwnName", "aLaunchThatNamesAnotherDestinationOpensPastTheGate", "theGateIsNeverGoneTo"] {
            XCTAssertTrue(tests.contains("@Test func \(test)()"), test)
        }
        XCTAssertFalse(tests.contains("aDestinationTheAppNoLongerHasReadsAsTheFirst"), "with a default nothing is decoded")

        // A page opens a sheet through the layout service, once the navigation is there.
        try await Fixture.call(Fixture.seerWithWallet, in: folder)
        XCTAssertTrue(try read(folder, "Components/Seer/Seer+Actions.swift").contains("layout.present(.wallet)"))

        // Made again with no gate, nothing of the gate is left: it lives only in files navigation writes whole.
        var plain = Fixture.seerNavigation
        plain.gate = nil
        plain.relays = nil
        plain.destinations = plain.destinations?.filter { !$0.hasSuffix(" gate") }
        try await Fixture.call(plain, in: folder)
        XCTAssertFalse(try read(folder, "Components/Home/Home+View.swift").contains("AppGate"))
        XCTAssertFalse(try read(folder, "Shared/Utility/AppDestination.swift").contains("opensPastGate"))
    }

    /// With sheets and no default, the tab on screen is still kept between launches, and one that is no longer a tab
    /// reads as the first; a default alone changes only where a plain launch opens.
    func testWithNoDefaultTheTabIsKeptAndADefaultAloneListsEveryDestination() async throws {
        let folder = try await app()
        var input = Fixture.navigation
        input.destinations = [#"recipes: RecipeList "Recipes" book"#, #"search: RecipeSearch "Search" magnifyingglass"#, #"settings: Settings "Settings" gearshape sheet"#]
        try await Fixture.call(input, in: folder)
        let center = try read(folder, "Services/LayoutService/LayoutService+Center.swift")
        XCTAssertTrue(center.contains("@Store(persist: \"persistence.Recipes.layout.0001\", autoSave: true, preload: true) var state: State"))
        XCTAssertTrue(center.contains("stored.isTab {\n                    destination = stored"))
        XCTAssertTrue(try read(folder, "Tests/LayoutOpsTests.swift").contains("aDestinationTheAppNoLongerHasReadsAsTheFirst"))
        XCTAssertFalse(try read(folder, "Shared/Utility/AppDestination.swift").contains("gate"))

        input.destinations = [#"recipes: RecipeList "Recipes" book"#, #"search: RecipeSearch "Search" magnifyingglass default"#]
        try await Fixture.call(input, in: folder)
        XCTAssertTrue(try read(folder, "Services/LayoutService/LayoutService+Center.swift").contains("destination = launch ?? .search"))
        XCTAssertFalse(try read(folder, "Shared/Utility/AppDestination.swift").contains("isTab"))
        XCTAssertTrue(try read(folder, "iOS/PlatformNavigationView.swift").contains("ForEach(AppDestination.allCases)"))
    }

    /// A gate is held by something real: each of the line and the condition without the other, a relay the project
    /// does not have, two defaults, two gates, no tab, a state field the service lacks: refused with every reason, and
    /// nothing written.
    func testAGateIsRefusedWithEveryReason() async throws {
        let folder = try Fixture.folder()
        try await Fixture.call(Fixture.seerProject, in: folder)
        try await Fixture.call(Fixture.account, in: folder)
        try await Fixture.call(Fixture.signIn, in: folder)
        for page in Fixture.seerPages { try await Fixture.call(page, in: folder) }
        func refusal(_ input: GraniteAppAgent.Input) async -> String {
            do {
                try await Fixture.call(input, in: folder)
                return ""
            } catch { return "\(error)" }
        }
        var noLine = Fixture.seerNavigation
        noLine.destinations = [#"library: Library "Library" books.vertical default"#, #"seer: Seer "Seer" sparkles default"#]
        noLine.relays = ["account: AccountService", "keys: KeychainService"]
        var text = await refusal(noLine)
        for reason in ["no destination is marked `gate`", "`KeychainService` is not in the project", "`library` and `seer` are both marked `default`"] {
            XCTAssertTrue(text.contains(reason), "\(reason) in \(text)")
        }
        var noCondition = Fixture.seerNavigation
        noCondition.gate = nil
        noCondition.destinations = (noCondition.destinations ?? []) + [#"welcome: Library "Welcome" hand.wave gate"#]
        text = await refusal(noCondition)
        for reason in ["`auth` is marked `gate`, and nothing holds it", "`auth` and `welcome` are both marked `gate`"] {
            XCTAssertTrue(text.contains(reason), "\(reason) in \(text)")
        }
        var unseen = Fixture.seerNavigation
        unseen.gate = "account.state.token == nil || session.isEmpty"
        text = await refusal(unseen)
        for reason in ["`account.state.token`, which AccountService's state does not have (it has `session`", "the gate reads `session`, which is not one of `relays`"] {
            XCTAssertTrue(text.contains(reason), "\(reason) in \(text)")
        }
        var noRelay = Fixture.seerNavigation
        noRelay.relays = nil
        text = await refusal(noRelay)
        XCTAssertTrue(text.contains("the gate reads `account`, which is not one of `relays`: name it there (`account: AccountService`)"), text)
        var noTab = Fixture.seerNavigation
        noTab.destinations = [#"auth: SignIn "Sign In" person gate"#, #"wallet: Wallet "Wallet" creditcard sheet"#]
        text = await refusal(noTab)
        XCTAssertTrue(text.contains("at least one is a tab"), text)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Shared/Utility/AppDestination.swift").path))
    }

    func testTheSplitStyleShowsADetailPaneAndWidensTheMacWindow() async throws {
        let folder = try await app()
        var input = Fixture.navigation
        input.style = .split
        input.destinations = [#"recipes: RecipeList "Recipes" book | Settings"#, #"search: RecipeSearch "Search" magnifyingglass"#]
        try await Fixture.call(input, in: folder)
        let destinations = try read(folder, "Shared/Utility/AppDestination.swift")
        XCTAssertTrue(destinations.contains("var detail: some View {"))
        XCTAssertTrue(destinations.contains("case .recipes: Settings()"))
        XCTAssertTrue(destinations.contains("default: ContentUnavailableView(\"Nothing Selected\", systemImage: \"sidebar.right\")"))
        XCTAssertTrue(try read(folder, "macOS/PlatformNavigationView.swift").contains("LayoutService.resizeWindow(width: detail == nil ? LayoutService.compactWidth : LayoutService.expandedWidth)"))
        XCTAssertTrue(try read(folder, "iOS/PlatformNavigationView.swift").contains("} content: {"))
    }

    func testNavigationRefusesAPageTheProjectDoesNotHave() async throws {
        let folder = try await app(pages: false)
        do {
            try await Fixture.call(Fixture.navigation, in: folder)
            XCTFail("a destination's page must exist")
        } catch {
            let text = "\(error)"
            for page in ["RecipeList", "RecipeSearch", "Settings"] { XCTAssertTrue(text.contains("`\(page)` is not in the project"), text) }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Shared/Utility/AppDestination.swift").path))
    }

    /// A destination is a page: a kit's view that needs values (loom's FeedView) is refused, pointing to a page that
    /// shows it; a view made with no arguments is taken (Margin, 2026-11-01).
    func testNavigationRefusesAViewThatNeedsValues() async throws {
        let folder = try await app()
        try """
        import SwiftUI

        struct DishFeed<Item: Identifiable>: View {
            let items: [Item]
            var body: some View { Text("") }
        }

        struct About: View {
            var body: some View { Text("About") }
        }
        """.write(to: folder.appendingPathComponent("Shared/Kit.swift"), atomically: true, encoding: .utf8)
        var input = Fixture.navigation
        input.destinations = [#"recipes: RecipeList "Recipes" book"#, #"dishes: DishFeed "Dishes" fork.knife"#, #"about: About "About" info.circle"#]
        do {
            try await Fixture.call(input, in: folder)
            XCTFail("a view that needs values is not a destination")
        } catch {
            let text = "\(error)"
            XCTAssertTrue(text.contains("`DishFeed` is a view that needs values to be made, not a page"), text)
            XCTAssertFalse(text.contains("`About`"), "a view made with no arguments is taken: \(text)")
        }
    }

    func testModalsReplaceTheHostTheRootViewApplies() async throws {
        let folder = try await app(pages: false)
        let inert = try read(folder, "Shared/Utility/ModalHosting.swift")
        XCTAssertTrue(inert.contains("func modalHosted() -> some View {\n        self\n    }"))
        try await Fixture.call(Fixture.modals, in: folder)
        let hosting = try read(folder, "Shared/Utility/ModalHosting.swift")
        XCTAssertTrue(hosting.contains(".modifier(ModalSheetHost(level: 0))") && hosting.contains(".modifier(ModalAlertHost())"))
        let service = try read(folder, "Services/ModalService/ModalService.swift")
        for helper in ["func sheet<Content: View>(id: String = \"sheet\", detents: [ModalDetent] = [.large]", "func alert(_ alert: ModalAlert)",
                       "func toast(_ message: String, style: ModalToast.Style = .info)", "func travel<Content: View>(id: String, title: String",
                       "func minimize(_ id: String)", "func restore(_ id: String)", "func close(_ id: String)",
                       "#if os(macOS)\n    /// Opens `content` in a window of its own", "static let views = TransientRegistry<AnyView>()"] {
            XCTAssertTrue(service.contains(helper), helper)
        }
        XCTAssertTrue(try read(folder, "Shared/Utility/AppRoot.swift").contains("@Relay(.silence) var modals: ModalService"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Tests/ModalOpsTests.swift").path))
    }

    func testAKitInAnAppIsLinkedIntoBothApps() async throws {
        let folder = try await app(pages: false)
        let result = try await Fixture.call(Fixture.kit, in: folder)
        XCTAssertTrue(result.paths.contains(folder.appendingPathComponent("Recipes.xcodeproj/project.pbxproj").path), "\(result.paths)")
        let manifest = try read(folder, "Packages/RecipeKit/Package.swift")
        XCTAssertTrue(manifest.contains(".package(url: \"\(GranitePin.url)\", revision: \"\(GranitePin.revision)\")"))
        XCTAssertTrue(manifest.contains("platforms: [.iOS(.v17), .macOS(.v14)]"))
        XCTAssertTrue(manifest.contains("swiftSettings: [.swiftLanguageMode(.v5)]"))
        let project = try Pbxproj(try read(folder, "Recipes.xcodeproj/project.pbxproj"))
        XCTAssertEqual(project.objects("XCLocalSwiftPackageReference").first?.string("relativePath"), "Packages/RecipeKit")
        for target in project.applicationTargets {
            XCTAssertTrue(target.object.list("packageProductDependencies").compactMap { project.objects[$0]?.string("productName") }.contains("RecipeKit"))
        }
        do {
            try await Fixture.call(Fixture.kit, in: folder)
            XCTFail("a kit is never written over")
        } catch {
            XCTAssertTrue("\(error)".contains("already holds a Package.swift"))
        }
    }

    func testAKitOnItsOwn() async throws {
        let folder = try Fixture.folder()
        let result = try await Fixture.call(GraniteAppAgent.Input(make: .package, name: "Ledger"), in: folder)
        XCTAssertEqual(Set(result.paths.map { String($0.dropFirst(folder.path.count + 1)) }),
                       ["Package.swift", "Sources/Ledger/LedgerRoot.swift", "Tests/LedgerTests/LedgerTests.swift", ".gitignore"])
        try await Fixture.call(GraniteAppAgent.Input(make: .service, type: "Entries", state: ["entries [String] = []"], events: ["empty() -> entries = []"]), in: folder)
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Sources/Ledger/Services/EntriesService/EntriesService.swift").path),
                      "with no app, a service goes in the kit the folder is")
    }

    func testLinkBringsGraniteIntoAClassicProjectOnce() async throws {
        let folder = try Fixture.folder()
        try ClassicProject.write(to: folder)
        let result = try await Fixture.call(GraniteAppAgent.Input(make: .link), in: folder)
        let project = try Pbxproj(try read(folder, "Greeter.xcodeproj/project.pbxproj"))
        XCTAssertNil(Pbxproj.lint(project.text))
        let app = project.applicationTargets[0], tests = project.targets.first { $0.isUnitTests }!
        XCTAssertEqual(app.object.list("packageProductDependencies").compactMap { project.objects[$0]?.string("productName") }, ["Granite", "GraniteAgents"])
        XCTAssertEqual(tests.object.list("packageProductDependencies"), [], "only app targets link Granite")
        XCTAssertEqual(project.settings(of: app)?["SWIFT_VERSION"]?.string, "5.0", "reducers hold relays: the app builds in Swift 5")
        XCTAssertEqual(project.settings(of: tests)?["SWIFT_VERSION"]?.string, "6.0")
        let sources = project.phase("PBXSourcesBuildPhase", of: app)!.list("files").compactMap { project.objects[$0]?.string("fileRef") }
            .compactMap { project.objects[$0]?.string("path") }
        for file in ["AppRoot.swift", "Home.swift", "Home+View.swift", "EnvironmentService.Boot.swift", "ConfigOps.swift", "ModalHosting.swift"] {
            XCTAssertTrue(sources.contains(file), "\(file) is compiled into the app")
        }
        let testSources = project.phase("PBXSourcesBuildPhase", of: tests)!.list("files").compactMap { project.objects[$0]?.string("fileRef") }
            .compactMap { project.objects[$0]?.string("path") }
        XCTAssertEqual(Set(testSources), ["GreeterTests.swift", "BootTests.swift"])
        XCTAssertTrue(try read(folder, "Greeter/GreeterApp.swift").contains("WindowGroup {\n            Home {\n                ContentView()\n            }\n        }"))
        XCTAssertTrue(try read(folder, "Greeter/Components/Home/Home.swift").contains("init<Content: View>(@ViewBuilder content: @escaping () -> Content)"))
        XCTAssertTrue(try read(folder, "Greeter/Components/Home/Home+View.swift").contains("case .ready:\n                content()"))
        XCTAssertTrue(result.notes.contains { $0.contains("Swift 5 language mode") })

        let before = project.text
        let again = try await Fixture.call(GraniteAppAgent.Input(make: .link), in: folder)
        XCTAssertEqual(again.paths, [], "a second link adds nothing")
        XCTAssertEqual(try read(folder, "Greeter.xcodeproj/project.pbxproj"), before)
    }

    /// A model that calls link in an app this agent made (Hearth, 2026-11-01) is told everything is in place, and
    /// nothing is written: the boot tests `make: project` wrote as `<App>Tests.swift` are found by what they hold.
    func testLinkAddsNothingToAnAppThisAgentMade() async throws {
        let folder = try Fixture.folder()
        try await Fixture.call(GraniteAppAgent.Input(make: .project, name: "Larder", bundleId: "com.example.larder"), in: folder)
        let before = try read(folder, "Larder.xcodeproj/project.pbxproj")
        let again = try await Fixture.call(GraniteAppAgent.Input(make: .link), in: folder)
        XCTAssertEqual(again.paths, [], "link adds nothing to a Granite app")
        XCTAssertTrue(again.notes.contains { $0.contains("nothing to add") }, "\(again.notes)")
        XCTAssertEqual(try read(folder, "Larder.xcodeproj/project.pbxproj"), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Tests/BootTests.swift").path))
    }

    func testLinkLeavesAWindowGroupThatIsNotPlainAndSaysWhatToChange() async throws {
        let folder = try Fixture.folder()
        try ClassicProject.write(to: folder)
        let app = """
            import SwiftUI

            @main
            struct GreeterApp: App {
                var body: some Scene {
                    WindowGroup {
                        ContentView()
                            .frame(minWidth: 400)
                    }
                }
            }

            """
        try app.write(to: folder.appendingPathComponent("Greeter/GreeterApp.swift"), atomically: true, encoding: .utf8)
        let result = try await Fixture.call(GraniteAppAgent.Input(make: .link), in: folder)
        XCTAssertEqual(try read(folder, "Greeter/GreeterApp.swift"), app)
        XCTAssertTrue(result.notes.contains { $0.contains("wrap what it shows in `Home { … }`") }, "\(result.notes)")
    }

    func testLinkRefusesWhereThereIsNoProject() async throws {
        let folder = try Fixture.folder()
        do {
            try await Fixture.call(GraniteAppAgent.Input(make: .link), in: folder)
            XCTFail("there is nothing to link into")
        } catch {
            XCTAssertTrue("\(error)".contains("there is none here"))
        }
    }
}
