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

    /// Seer's launch contract (2026-11-15): a sub-destination opens its parent by alias and stays readable, the gate's
    /// aliases hold the gate, Profile goes up over the Models tab and Settings stacked on Profile when a launch names
    /// them, unanimated, and in use a sheet goes up over whatever is up and closes alone.
    func testLaunchAliasesAndSheetsOverATabOrASheet() async throws {
        let folder = try Fixture.folder()
        try await Fixture.call(Fixture.seerProject, in: folder)
        try await Fixture.call(Fixture.account, in: folder)
        try await Fixture.call(Fixture.signIn, in: folder)
        for page in Fixture.seerPages + [Fixture.seerSettings] { try await Fixture.call(page, in: folder) }
        let result = try await Fixture.call(Fixture.seerShell, in: folder)
        XCTAssertEqual(result.expected.map(\.name), ["auth", "library", "seer", "models", "profile", "settings", "wallet"], "an alias is not a destination")
        for note in ["`auth.signup`, `auth.code` open `auth` (on the gate); `void.reply` opens `seer`; `model.edit` opens `models`; `settings.feedback` opens `settings`",
                     "`-destination profile` selects `models` with `profile` up", "`-destination settings` selects `models` and puts up `profile`, then `settings`, unanimated"] {
            XCTAssertTrue(result.notes.contains { $0.contains(note) }, "\(note) in \(result.notes)")
        }

        let destinations = try read(folder, "Shared/Utility/AppDestination.swift")
        for line in ["    case auth\n    case library\n    case seer\n    case models\n    case profile\n    case settings\n    case wallet\n\n",
                     "static var launchArgument: AppDestination? {\n        UserDefaults.standard.string(forKey: \"destination\").flatMap(AppDestination.init(launchName:))",
                     "static let aliases: [(name: String, destination: AppDestination)] = [\n        (\"auth.signup\", .auth),\n        (\"auth.code\", .auth),\n"
                        + "        (\"void.reply\", .seer),\n        (\"settings.feedback\", .settings),\n        (\"model.edit\", .models),\n    ]",
                     "static var launchNames: [String] { allCases.map(\\.rawValue) + aliases.map(\\.name) }", "init?(launchName: String) {",
                     "case .profile: .models\n        case .settings: .profile\n        default: nil",
                     "`-destination auth.signup` holds the gate as `-destination auth` does", "return destination != gate"] {
            XCTAssertTrue(destinations.contains(line), line)
        }
        let center = try read(folder, "Services/LayoutService/LayoutService+Center.swift")
        for line in ["var sheets: [AppDestination] = []", "while let sheet = under, sheet.isSheet, !sheets.contains(sheet) {\n                    sheets.insert(sheet, at: 0)\n"
                        + "                    under = sheet.over\n                }", "destination = under.flatMap { $0.isTab ? $0 : nil } ?? .seer"] {
            XCTAssertTrue(center.contains(line), line)
        }
        XCTAssertTrue(try read(folder, "Services/LayoutService/Reducers/LayoutService.Set.swift").contains("case sheet(AppDestination?)\n"
            + "                /// The sheets up, the lowest first: what a swipe down leaves.\n                case sheets([AppDestination])"))
        let ops = try read(folder, "Services/LayoutService/Ops/LayoutOps.swift")
        for line in ["putUp(destination, on: &state)", "state.sheets.removeLast()", "state.sheets.removeSubrange((index + 1)...)", "// The gate is shown while it holds"] {
            XCTAssertTrue(ops.contains(line), line)
        }
        XCTAssertTrue(try read(folder, "Services/LayoutService/LayoutService.swift").contains("/// Closes the sheet on top, leaving the one under it.\n    func closeSheet() {"))
        for platform in ["iOS", "macOS"] {
            let view = try read(folder, "\(platform)/PlatformNavigationView.swift")
            for line in [".modifier(LayoutSheetHost(level: 0))", "private struct LayoutSheetHost: ViewModifier {", ".sheet(item: $shown) { destination in",
                         ".modifier(LayoutSheetHost(level: level + 1))", "unanimated.disablesAnimations = true", "withTransaction(unanimated) { shown = sheet }",
                         "layout.set(.sheets(Array(layout.state.sheets.prefix(level))))", "Button(\"Close\", systemImage: \"xmark\") { layout.closeSheet() }"] {
                XCTAssertTrue(view.contains(line), "\(platform): \(line)")
            }
            XCTAssertFalse(view.contains(".sheet(item: layout.binding(\\.sheet)"), platform)
        }
        XCTAssertTrue(try read(folder, "Components/Home/Home+View.swift").contains("/// So does a launch alias of the gate's destination: `-destination auth.signup`, `-destination auth.code`."))
        let tests = try read(folder, "Tests/LayoutOpsTests.swift")
        for line in ["@Test func aSheetGoesUpOverWhateverIsUpAndClosesAlone()", "#expect(state.sheets == [.profile, .settings], \"a sheet goes up over the sheet that is up\")",
                     "@Test func aLaunchThatAsksForASheetPutsUpWhatItGoesOver()",
                     "state = LayoutService.Center.State(launch: .settings)\n        #expect(state.destination == .models, \"-destination settings\")\n"
                        + "        #expect(state.sheets == [.profile, .settings], \"-destination settings\")",
                     "#expect(state.destination == .seer, \"-destination wallet\")\n        #expect(state.sheets == [.wallet], \"-destination wallet\")",
                     "for alias in AppDestination.aliases where alias.destination == .auth {",
                     "for name in AppDestination.launchNames where AppDestination(launchName: name) != .auth {", "@Test func anAliasOpensWhatItsDestinationOpens()"] {
            XCTAssertTrue(tests.contains(line), line)
        }
    }

    /// A launch name opens one place and a sheet goes up over something real: an alias that names nothing, a cycle, a
    /// name used twice, a sheet over nothing, over the gate, over itself, or two sheets over each other are refused with
    /// every reason, and nothing is written.
    func testAliasesAndOverAreRefusedWithEveryReason() async throws {
        let folder = try Fixture.folder()
        try await Fixture.call(Fixture.seerProject, in: folder)
        try await Fixture.call(Fixture.account, in: folder)
        try await Fixture.call(Fixture.signIn, in: folder)
        for page in Fixture.seerPages + [Fixture.seerSettings] { try await Fixture.call(page, in: folder) }
        func refusal(_ destinations: [String]) async -> String {
            var input = Fixture.seerShell
            input.destinations = [#"auth: SignIn "Sign In" person gate"#, #"library: Library "Library" books.vertical"#, #"seer: Seer "Seer" sparkles default"#,
                                  #"models: Models "Models" cpu"#] + destinations
            do {
                try await Fixture.call(input, in: folder)
                return ""
            } catch { return "\(error)" }
        }
        var text = await refusal([#"profile: Profile "Profile" person.crop.circle sheet over settings"#, #"settings: Settings "Settings" gearshape sheet over profile"#,
                                  #"wallet: Wallet "Wallet" creditcard sheet over nowhere"#,
                                  "auth.signup -> autth", "a.b -> c.d", "c.d -> a.b", "seer -> library", "void.reply -> seer", "void.reply -> library"])
        for reason in ["`auth.signup -> autth`: `autth` is neither a destination nor an alias", "`a.b -> c.d -> a.b` is a cycle",
                       "`seer` is a destination and an alias", "the alias `void.reply` is named twice", "`wallet` goes up over `nowhere`, which is not a destination",
                       "`profile` over `settings` over `profile` is a cycle"] {
            XCTAssertTrue(text.contains(reason), "\(reason) in \(text)")
        }
        text = await refusal([#"profile: Profile "Profile" person.crop.circle sheet over auth.code"#, #"wallet: Wallet "Wallet" creditcard sheet over wallet"#,
                              "auth.code -> auth"])
        for reason in ["`profile` goes up over `auth`, the gate", "`wallet` goes up over itself"] {
            XCTAssertTrue(text.contains(reason), "\(reason) in \(text)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Shared/Utility/AppDestination.swift").path))
    }

    /// A sheet at its own heights (Seer, 2026-11-15): a line's `detents` are the heights its sheet rests at, the first
    /// where it goes up (a launch's too) with the drag indicator showing, stacked on a tab or a sheet or not stacked at
    /// all; a sheet whose line names none goes up large with no indicator, as before.
    func testASheetRestsAtTheHeightsItsLineNamesAndGoesUpAtTheFirst() async throws {
        let folder = try Fixture.folder()
        try await Fixture.call(Fixture.seerProject, in: folder)
        try await Fixture.call(Fixture.account, in: folder)
        try await Fixture.call(Fixture.signIn, in: folder)
        for page in Fixture.seerPages + [Fixture.seerSettings] { try await Fixture.call(page, in: folder) }
        let result = try await Fixture.call(Fixture.seerDetents, in: folder)
        for note in ["`wallet`, `profile`, `settings` are sheets, with a close button: a page puts one up over whatever is up",
                     "sheet heights: `wallet` at medium then large; `profile` at fraction(0.6). Each goes up at the first its line names, on a launch too, "
                        + "with the drag indicator showing", "; `settings` goes up at the large detent alone"] {
            XCTAssertTrue(result.notes.contains { $0.contains(note) }, "\(note) in \(result.notes)")
        }
        let destinations = try read(folder, "Shared/Utility/AppDestination.swift")
        for line in ["    var detents: [PresentationDetent] {\n        switch self {\n        case .wallet: [.medium, .large]\n        case .profile: [.fraction(0.6)]\n"
                        + "        default: [.large]\n        }\n    }\n",
                     "    var dragIndicator: Visibility {\n        switch self {\n        case .wallet, .profile: .visible\n        default: .automatic\n        }\n    }\n"] {
            XCTAssertTrue(destinations.contains(line), line)
        }
        for platform in ["iOS", "macOS"] {
            let view = try read(folder, "\(platform)/PlatformNavigationView.swift")
            for line in [".modifier(LayoutSheetHost(level: level + 1))", ".modifier(LayoutSheetDetents(destination: destination))\n            }",
                         "private struct LayoutSheetDetents: ViewModifier {", "@State private var detent: PresentationDetent",
                         "_detent = State(initialValue: destination.detents.first ?? .large)",
                         "content\n            .presentationDetents(Swift.Set(destination.detents), selection: $detent)\n            .presentationDragIndicator(destination.dragIndicator)"] {
                XCTAssertTrue(view.contains(line), "\(platform): \(line)")
            }
            XCTAssertFalse(view.contains(".presentationDetents([.large])"), "\(platform): every sheet goes up at its own heights")
        }
        let tests = try read(folder, "Tests/LayoutOpsTests.swift")
        for line in ["import Foundation\nimport SwiftUI\nimport Testing\n", "@Test func aSheetRestsAtTheHeightsItsLineNamesAndGoesUpAtTheFirst() {",
                     "#expect(AppDestination.wallet.detents == [.medium, .large], \"-destination wallet goes up at medium\")",
                     "#expect(AppDestination.profile.detents == [.fraction(0.6)], \"-destination profile goes up at fraction(0.6)\")",
                     "#expect(AppDestination.profile.dragIndicator == .visible)",
                     "#expect(AppDestination.settings.detents == [.large], \"a sheet whose line names none goes up large\")",
                     "#expect(AppDestination.settings.dragIndicator == .automatic)", "state = LayoutService.Center.State(launch: .settings)"] {
            XCTAssertTrue(tests.contains(line), line)
        }

        // Sheets that do not stack go up at their own heights through the plain host.
        var plain = Fixture.seerNavigation
        plain.destinations = plain.destinations?.map { $0.hasPrefix("wallet:") ? $0 + " detents height(320) large" : $0 }
        let flat = try await Fixture.call(plain, in: folder)
        XCTAssertTrue(flat.notes.contains { $0.contains("sheet heights: `wallet` at height(320) then large.") && $0.hasSuffix("; `profile` goes up at the large detent alone") },
                      "\(flat.notes)")
        XCTAssertTrue(try read(folder, "Shared/Utility/AppDestination.swift").contains("case .wallet: [.height(320), .large]\n        default: [.large]"))
        for platform in ["iOS", "macOS"] {
            let view = try read(folder, "\(platform)/PlatformNavigationView.swift")
            XCTAssertTrue(view.contains(".sheet(item: layout.binding(\\.sheet) { .sheet($0) }) { destination in"), platform)
            XCTAssertTrue(view.contains(".modifier(LayoutSheetDetents(destination: destination))\n        }"), platform)
            XCTAssertTrue(view.contains("private struct LayoutSheetDetents: ViewModifier {"), platform)
            XCTAssertFalse(view.contains("LayoutSheetHost") || view.contains(".presentationDetents([.large])"), platform)
        }
    }

    /// A page that draws its own close and aliases that name a height (Seer's floor, 2026-11-15): `bare` keeps the page in
    /// its stack and adds no close button for it, in both hosts on both platforms, a swipe still closing it; an alias's
    /// height puts its sheet up at it on a launch, once, with each sheet under it that rests there too; a height on an
    /// alias to a tab or the gate, to a sheet with no heights, or one its sheet does not rest at is refused.
    func testABareSheetAddsNoCloseAndAnAliasNamesTheHeightItsSheetOpensAt() async throws {
        let folder = try Fixture.folder()
        try await Fixture.call(Fixture.seerProject, in: folder)
        try await Fixture.call(Fixture.account, in: folder)
        try await Fixture.call(Fixture.signIn, in: folder)
        for page in Fixture.seerPages + [Fixture.seerSettings] { try await Fixture.call(page, in: folder) }
        let result = try await Fixture.call(Fixture.seerSheets, in: folder)
        for note in ["`wallet` draws its own close (`bare`): its sheet adds no close button, and a swipe down still closes it",
                     "alias heights: `-destination wallet.full` puts `wallet` up at large; `-destination profile.full` puts `wallet` and `profile` up at large, once"] {
            XCTAssertTrue(result.notes.contains { $0.contains(note) }, "\(note) in \(result.notes)")
        }
        let destinations = try read(folder, "Shared/Utility/AppDestination.swift")
        for line in ["    static let aliasDetents: [String: [AppDestination: PresentationDetent]] = [\n        \"wallet.full\": [.wallet: .large],\n"
                        + "        \"profile.full\": [.wallet: .large, .profile: .large],\n    ]\n",
                     "@MainActor static func launchDetent(for destination: AppDestination) -> PresentationDetent? {",
                     "let detent = aliasDetents[name]?[destination],\n              launchDetentsGiven.insert(destination).inserted else { return nil }",
                     "@MainActor private static var launchDetentsGiven: Swift.Set<AppDestination> = []",
                     "    var closesItself: Bool {\n        switch self {\n        case .wallet: true\n        default: false\n        }\n    }\n"] {
            XCTAssertTrue(destinations.contains(line), line)
        }
        for platform in ["iOS", "macOS"] {
            let view = try read(folder, "\(platform)/PlatformNavigationView.swift")
            for line in [".toolbar {\n                            if !destination.closesItself {\n                                ToolbarItem(placement: .cancellationAction) {",
                         "_detent = State(initialValue: AppDestination.launchDetent(for: destination) ?? destination.detents.first ?? .large)"] {
                XCTAssertTrue(view.contains(line), "\(platform): \(line)")
            }
        }
        let tests = try read(folder, "Tests/LayoutOpsTests.swift")
        for line in ["@Test func anAliasPutsItsSheetUpAtTheHeightItNames() {",
                     "#expect(AppDestination.aliasDetents[\"profile.full\"] == [.wallet: .large, .profile: .large], \"-destination profile.full\")",
                     "@Test func aSheetWhosePageDrawsItsOwnCloseGetsNoCloseButton() {", "#expect(AppDestination.wallet.closesItself)",
                     "#expect(!AppDestination.profile.closesItself, \"a sheet whose line does not say bare gets the close button\")"] {
            XCTAssertTrue(tests.contains(line), line)
        }

        // A bare sheet in the plain host, its sheets not stacked.
        var plain = Fixture.seerNavigation
        plain.destinations = plain.destinations?.map { $0.hasPrefix("wallet:") ? $0 + " bare" : $0 }
        try await Fixture.call(plain, in: folder)
        for platform in ["iOS", "macOS"] {
            let view = try read(folder, "\(platform)/PlatformNavigationView.swift")
            XCTAssertTrue(view.contains(".toolbar {\n                        if !destination.closesItself {\n                            ToolbarItem(placement: .cancellationAction) {"), platform)
            XCTAssertFalse(view.contains("LayoutSheetDetents") || view.contains("LayoutSheetHost"), platform)
        }

        func refusal(_ lines: [String]) async -> String {
            var input = Fixture.seerSheets
            input.destinations = Array(input.destinations!.prefix(7)) + lines
            do {
                try await Fixture.call(input, in: folder)
                return ""
            } catch { return "\(error)" }
        }
        let text = await refusal(["library.top -> library large", "auth.big -> auth large", "settings.full -> settings large", "wallet.tall -> wallet fraction(0.9)",
                                  "wallet.again -> wallet.tall"])
        for reason in ["`library.top` opens `library` at large, and `library` is a tab: a height is a sheet's",
                       "`auth.big` opens `auth` at large, and `auth` is the gate", "`settings.full` opens `settings` at large, and `settings` names no `detents`",
                       "`wallet.tall` opens `wallet` at fraction(0.9), a height `wallet` does not rest at (it rests at medium, large)",
                       "`wallet.again` opens `wallet` at fraction(0.9)"] {
            XCTAssertTrue(text.contains(reason), "\(reason) in \(text)")
        }
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

    /// Seer's shell as the original draws it: each tab's image alone, the mark drawn as the middle tab's image in its own
    /// colours, the accent on the selected tab, a light impact on a tab change, and the first-run layer over the tabs and
    /// under every sheet; with icons alone and no drawn image the symbols stay; an overlay or a drawn view the project
    /// does not have is refused.
    func testTheTabBarDrawsTheMarkIconsAloneAndHostsAnOverlay() async throws {
        let folder = try Fixture.folder()
        try await Fixture.call(Fixture.seerProject, in: folder)
        try await Fixture.call(Fixture.account, in: folder)
        try await Fixture.call(Fixture.signIn, in: folder)
        for page in Fixture.seerPages + [Fixture.seerSettings] { try await Fixture.call(page, in: folder) }

        var missing = ""
        do { try await Fixture.call(Fixture.seerChrome, in: folder) } catch { missing = "\(error)" }
        for reason in ["`SeerMark` is not in the project: the view drawn as `seer`'s image is one the app has",
                       "the overlay `Onboarding` is not in the project: make the page first (`make: component`, `type: Onboarding`)"] {
            XCTAssertTrue(missing.contains(reason), "\(reason) in \(missing)")
        }

        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Shared/Views"), withIntermediateDirectories: true)
        try Fixture.seerMark.write(to: folder.appendingPathComponent("Shared/Views/SeerMark.swift"), atomically: true, encoding: .utf8)
        try await Fixture.call(Fixture.seerOnboarding, in: folder)
        let result = try await Fixture.call(Fixture.seerChrome, in: folder)
        for note in ["`seer`'s image is `SeerMark().frame(width: 30, height: 30)`, drawn once at the screen's scale in its own colours",
                     "the tab bar shows each tab's image alone",
                     "the selected tab takes `Color.accentColor`, and so does each sheet's stack (iOS), as the original presents its sheets from inside its tinted tab view",
                     "a tab change on iPhone gives a light impact", "`Onboarding()` is drawn over the tabs, under every sheet"] {
            XCTAssertTrue(result.notes.contains { $0.contains(note) }, "\(note) in \(result.notes)")
        }
        let destinations = try read(folder, "Shared/Utility/AppDestination.swift")
        for line in ["@MainActor func image(scale: CGFloat) -> Image {", "case .library: Image(systemName: \"books.vertical.fill\")",
                     "case .seer: Self.drawn(SeerMark().frame(width: 30, height: 30), scale: scale)",
                     "case .models: Image(systemName: \"externaldrive.fill.badge.person.crop\")", "let renderer = ImageRenderer(content: view)",
                     "renderer.scale = scale", "return Image(uiImage: image).renderingMode(.original)", "return Image(nsImage: image).renderingMode(.original)"] {
            XCTAssertTrue(destinations.contains(line), line)
        }
        XCTAssertFalse(destinations.contains("var symbol: String {"), "a drawn image replaces the symbols' list")
        let iOS = try read(folder, "iOS/PlatformNavigationView.swift")
        for line in ["@Environment(\\.displayScale) private var displayScale", "TabView(selection: layout.binding(\\.destination) { .destination($0) }) {",
                     ".tabItem { Label { Text(\"\") } icon: { destination.image(scale: displayScale) } }", "        }\n        .tint(Color.accentColor)\n",
                     ".sensoryFeedback(.impact(weight: .light), trigger: layout.state.destination)", ".overlay { Onboarding() }\n        .modifier(LayoutSheetHost(level: 0))",
                     // The original presents its sheets from inside its tinted TabView, so each sheet's stack takes the tint.
                     "                }\n                .tint(Color.accentColor)\n                .modifier(LayoutSheetHost(level: level + 1))"] {
            XCTAssertTrue(iOS.contains(line), "iOS: \(line)")
        }
        XCTAssertFalse(try read(folder, "Components/Home/Home+View.swift").contains(".tint("), "the gate keeps the system's tint, as the original's sign-in does")
        let macOS = try read(folder, "macOS/PlatformNavigationView.swift")
        for line in ["@Environment(\\.displayScale) private var displayScale", "Label { Text(destination.title) } icon: { destination.image(scale: displayScale) }",
                     ".overlay { Onboarding() }"] {
            XCTAssertTrue(macOS.contains(line), "macOS: \(line)")
        }
        XCTAssertFalse(macOS.contains("sensoryFeedback"), "the Mac has no tab bar to feel")
        XCTAssertFalse(macOS.contains(".tint("), "the Mac has no tab bar whose tint its sheets take")
        var sidebar = Fixture.seerChrome
        sidebar.style = .sidebar
        try await Fixture.call(sidebar, in: folder)
        XCTAssertFalse(try read(folder, "iOS/PlatformNavigationView.swift").contains(".tint("), "with no tab bar the tint is left out, the sheets' too")

        var icons = Fixture.seerShell
        icons.tabBar = .icons
        try await Fixture.call(icons, in: folder)
        let plain = try read(folder, "iOS/PlatformNavigationView.swift")
        XCTAssertTrue(plain.contains(".tabItem { Label(\"\", systemImage: destination.symbol) }"), plain)
        XCTAssertFalse(plain.contains("displayScale") || plain.contains(".overlay {") || plain.contains(".tint(") || plain.contains("sensoryFeedback"), plain)
        XCTAssertTrue(try read(folder, "Shared/Utility/AppDestination.swift").contains("var symbol: String {"))
    }

    /// The toasts' own window is opt-in (Seer, 2026-11-15): `toasts: window` hosts them on iOS in a passthrough window
    /// one level above alerts, the four styles in the system's symbols, each a card as the original draws it with a
    /// subtitle when given, in `toastDesign`; the Mac keeps the overlay. Made again without it, the files are as they
    /// were; `toastDesign` without the window is refused.
    func testTheToastWindowIsOptIn() async throws {
        let folder = try await app(pages: false)
        let result = try await Fixture.call(Fixture.seerToasts, in: folder)
        XCTAssertTrue(result.types.contains("ModalToastWindow"), "\(result.types)")
        XCTAssertTrue(result.notes.contains { $0.contains("one level above alerts (`.alert + 1`)") }, "\(result.notes)")
        let hosting = try read(folder, "Shared/Utility/ModalHosting.swift")
        for line in ["final class ModalToastWindow: UIWindow {", "window.windowLevel = .alert + 1", "window.rootViewController = host",
                     "override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {\n        toastFrame.contains(point)",
                     "#if os(iOS)\n            .background(ModalToastAnchor())\n            #else\n            .overlay(alignment: .top) {",
                     ".modifier(ModalSheetHost(level: 0))", "toasts?.overrideUserInterfaceStyle = style"] {
            XCTAssertTrue(hosting.contains(line), line)
        }
        let toast = try read(folder, "Services/ModalService/Views/ModalToastView.swift")
        for symbol in ["checkmark.circle.fill", "xmark.circle.fill", "exclamationmark.triangle.fill", "info.circle.fill"] {
            XCTAssertTrue(toast.contains("\"\(symbol)\""), symbol)
        }
        // The original's toast (Shared/Views/Toast/ToastView.swift, ToastService.swift): a card as wide as the screen.
        for line in ["HStack(spacing: 12) {", ".font(.system(size: 22, weight: .semibold))", ".background(.ultraThinMaterial)",
                     ".clipShape(RoundedRectangle(cornerRadius: 24))", ".shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)",
                     ".padding(.horizontal, 16)", "case .info: .blue", "VStack(alignment: .leading, spacing: 2) {",
                     ".font(.system(.headline, design: .serif, weight: .regular))", "if let subtitle = toast.subtitle {",
                     ".font(.system(.caption, design: .serif, weight: .light))\n                        .foregroundStyle(.secondary)\n                        .lineLimit(2)"] {
            XCTAssertTrue(toast.contains(line), line)
        }
        XCTAssertTrue(hosting.contains(".animation(.spring(response: 0.4, dampingFraction: 0.8), value: toasts)"), hosting)
        XCTAssertTrue(try read(folder, "Services/ModalService/Models/ModalToast.swift").contains("    var message: String\n    /// A second line under the message, smaller; none when left out.\n    var subtitle: String? = nil\n    var style: Style"))
        XCTAssertTrue(try read(folder, "Services/ModalService/ModalService.swift").contains(
            "func toast(_ message: String, subtitle: String? = nil, style: ModalToast.Style = .info) {\n        let toast = ModalToast(message: message, subtitle: subtitle, style: style)"))
        var plain = Fixture.seerToasts
        plain.toastDesign = nil
        try await Fixture.call(plain, in: folder)
        XCTAssertTrue(try read(folder, "Services/ModalService/Views/ModalToastView.swift").contains(".font(.system(.headline, design: .default, weight: .regular))"))
        var designOnly = Fixture.modals
        designOnly.toastDesign = .serif
        do {
            try await Fixture.call(designOnly, in: folder)
            XCTFail("`toastDesign` without the window is refused")
        } catch {
            XCTAssertTrue("\(error)".contains("`toastDesign` is the type of the toasts' own window: add `toasts: window`"), "\(error)")
        }

        try await Fixture.call(Fixture.modals, in: folder)
        XCTAssertEqual(try read(folder, "Shared/Utility/ModalHosting.swift"), ModalTemplates.hosting)
        XCTAssertEqual(try read(folder, "Services/ModalService/Views/ModalToastView.swift"), ModalTemplates.toastView)
        XCTAssertEqual(try read(folder, "Services/ModalService/Models/ModalToast.swift"), ModalTemplates.toast)
        XCTAssertEqual(try read(folder, "Services/ModalService/ModalService.swift"), ModalTemplates.modalService)
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
