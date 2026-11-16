import Foundation
import XCTest
@testable import GraniteAgent

/// The output built and run as a person's app would be: a recipe app made call by call (a project, a kit, services
/// with an expression and with a body from the model, every page layout, navigation and modals), its Loom layout
/// checked, built and tested on macOS, built for the iOS simulator, its kit tested with SwiftPM; Seer's shell (a
/// default tab, sheets and a sign-in gate) built and tested the same way, again with launch aliases, a sheet over a
/// tab, a sheet over a sheet and the toast window, and again with sheets at their own heights, a medium one over a tab
/// and a fraction one stacked on it, the first drawing its own close, aliases naming heights and the tab bar's tint,
/// and once more with the pages that move the app made before the navigation; and a fresh Xcode project linked and
/// built.
/// Gated (`GRANITE_BUILD=1`): a build takes minutes and fetches Granite.
final class GraniteBuildTests: XCTestCase {
    /// Where builds keep their packages between runs, under the process's temporary files.
    private let packages = FileManager.default.temporaryDirectory.appendingPathComponent("granite-agent-packages", isDirectory: true)

    private func xcodebuild(_ arguments: [String], in folder: URL, derived: URL, home: URL? = nil) throws -> Shell.Run {
        var environment: [String: String] = [:]
        // The test host is the app: it boots and saves its settings, under a home of the test's own, not the person's.
        if let home { environment["TEST_RUNNER_CFFIXED_USER_HOME"] = home.path }
        return try Shell.run(["xcrun", "xcodebuild"] + arguments + ["-derivedDataPath", derived.path, "-clonedSourcePackagesDirPath", packages.path,
                                                                    "-skipPackagePluginValidation", "-skipMacroValidation"], in: folder, environment: environment)
    }

    func testTheRecipeAppBuildsAndItsTestsPassOnBothPlatforms() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GRANITE_BUILD"] == "1", "set GRANITE_BUILD=1 to build the output")
        let folder = try Fixture.folder()
        let app = folder.appendingPathComponent("Recipes")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)

        try await Fixture.call(Fixture.project, in: app)
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Shared/Models"), withIntermediateDirectories: true)
        try Fixture.recipe.write(to: app.appendingPathComponent("Shared/Models/Recipe.swift"), atomically: true, encoding: .utf8)
        let model = Fixture.model()
        try await Fixture.call(Fixture.kit, in: app)
        try await Fixture.call(Fixture.recipesService, in: app)
        try await Fixture.call(Fixture.pantry, in: app, model: model)
        for page in [Fixture.recipeList, Fixture.settings, Fixture.search, Fixture.grid, Fixture.detail, Fixture.compose, Fixture.tabs, Fixture.browser, Fixture.today] {
            try await Fixture.call(page, in: app, model: model)
        }
        try await Fixture.call(Fixture.navigation, in: app)
        try await Fixture.call(Fixture.modals, in: app)
        XCTAssertEqual(model.asked.count, 4, "the pantry's work twice (its first answer does not parse), a subview, a page")

        let layout = try Shell.run(["python3", NSString(string: "~/.claude/skills/loom-app-architecture/scripts/check_layout.py").expandingTildeInPath, app.path], in: folder)
        XCTAssertTrue(layout.log.contains("0 error(s)"), layout.log)

        let derived = folder.appendingPathComponent("DerivedData")
        let home = folder.appendingPathComponent("home")
        let mac = try xcodebuild(["-project", "Recipes.xcodeproj", "-scheme", "Recipes-macOS", "-destination", "platform=macOS",
                                  "CODE_SIGNING_ALLOWED=NO", "-skip-testing:RecipesUITests-macOS", "build", "test"], in: app, derived: derived, home: home)
        XCTAssertEqual(mac.status, 0, Shell.digest(mac.log))
        XCTAssertTrue(mac.log.contains("** TEST SUCCEEDED **"), Shell.digest(mac.log))
        XCTAssertTrue(mac.log.contains("Test run with 27 tests in 4 suites passed"), Shell.digest(mac.log))
        XCTAssertFalse(mac.log.contains(": warning: "), "the app builds without a warning: \(mac.log.components(separatedBy: "\n").filter { $0.contains(": warning: ") }.prefix(5))")
        XCTAssertTrue(FileManager.default.fileExists(atPath: home.appendingPathComponent("Library/Application Support/com.example.recipes/granite-db").path),
                      "the app ran, and kept its settings under the test's home")

        let iOS = try xcodebuild(["-project", "Recipes.xcodeproj", "-scheme", "Recipes-iOS", "-destination", "generic/platform=iOS Simulator", "build", "build-for-testing"],
                                 in: app, derived: derived)
        XCTAssertEqual(iOS.status, 0, Shell.digest(iOS.log))

        let kit = try Shell.run(["swift", "test", "--scratch-path", folder.appendingPathComponent("kit-build").path], in: app.appendingPathComponent("Packages/RecipeKit"))
        XCTAssertEqual(kit.status, 0, Shell.digest(kit.log))
        XCTAssertTrue(kit.log.contains("Test run with 7 tests in 2 suites passed"), Shell.digest(kit.log))
        // What a passing build leaves is only build products; a failing one keeps them to be read.
        if testRun?.totalFailureCount == 0 { [derived, folder.appendingPathComponent("kit-build")].forEach { try? FileManager.default.removeItem(at: $0) } }
    }

    /// Seer's shell (2026-11-15): Sign In until there is a session, three tabs with the middle one where a plain launch
    /// opens, two sheets over them and a page that puts one up; built and its tests run on macOS (the layout's default,
    /// sheet and gate rules among them), built for the iOS simulator.
    func testTheSeerShellBuildsOnBothPlatforms() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GRANITE_BUILD"] == "1", "set GRANITE_BUILD=1 to build the output")
        let folder = try Fixture.folder()
        let app = folder.appendingPathComponent("Seer")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try await Fixture.call(Fixture.seerProject, in: app)
        try await Fixture.call(Fixture.account, in: app)
        try await Fixture.call(Fixture.signIn, in: app)
        for page in Fixture.seerPages { try await Fixture.call(page, in: app) }
        try await Fixture.call(Fixture.seerNavigation, in: app)
        try await Fixture.call(Fixture.seerWithWallet, in: app)

        let derived = folder.appendingPathComponent("DerivedData")
        let mac = try xcodebuild(["-project", "Seer.xcodeproj", "-scheme", "Seer-macOS", "-destination", "platform=macOS", "CODE_SIGNING_ALLOWED=NO",
                                  "-skip-testing:SeerUITests-macOS", "build", "test"], in: app, derived: derived, home: folder.appendingPathComponent("home"))
        XCTAssertEqual(mac.status, 0, Shell.digest(mac.log))
        XCTAssertTrue(mac.log.contains("** TEST SUCCEEDED **"), Shell.digest(mac.log))
        for test in ["aPlainLaunchOpensOnTheDefault", "aLaunchThatAsksForASheetOpensItOverTheDefaultTab", "aLaunchThatNamesAnotherDestinationOpensPastTheGate"] {
            XCTAssertTrue(mac.log.contains("Test \(test)() passed"), test)
        }
        XCTAssertFalse(mac.log.contains(": warning: "), "the app builds without a warning: \(mac.log.components(separatedBy: "\n").filter { $0.contains(": warning: ") }.prefix(5))")
        let iOS = try xcodebuild(["-project", "Seer.xcodeproj", "-scheme", "Seer-iOS", "-destination", "generic/platform=iOS Simulator", "build", "build-for-testing"],
                                 in: app, derived: derived)
        XCTAssertEqual(iOS.status, 0, Shell.digest(iOS.log))
        if testRun?.totalFailureCount == 0 { try? FileManager.default.removeItem(at: derived) }
    }

    /// Seer's launch contract (2026-11-15): launch aliases (the gate's among them), Profile over the Models tab and
    /// Settings stacked on Profile when a launch names them, a page that puts Wallet up, and the toasts in a window of
    /// their own one level above alerts; and its shell as the original draws it: the tabs' images alone, the mark drawn
    /// as the middle tab's image, the accent on the selected tab, a light impact on a tab change, the first-run layer
    /// over the tabs. Built and its tests run on macOS (the alias, stacked-sheet and gate rules among them), built for
    /// the iOS simulator, where the toast window, the tab bar and its feedback are compiled.
    func testTheSeerShellWithAliasesSheetsOverSheetsTheDrawnTabAndTheToastWindowBuilds() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GRANITE_BUILD"] == "1", "set GRANITE_BUILD=1 to build the output")
        let folder = try Fixture.folder()
        let app = folder.appendingPathComponent("Seer")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try await Fixture.call(Fixture.seerProject, in: app)
        try await Fixture.call(Fixture.account, in: app)
        try await Fixture.call(Fixture.signIn, in: app)
        for page in Fixture.seerPages + [Fixture.seerSettings, Fixture.seerOnboarding] { try await Fixture.call(page, in: app) }
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Shared/Views"), withIntermediateDirectories: true)
        try Fixture.seerMark.write(to: app.appendingPathComponent("Shared/Views/SeerMark.swift"), atomically: true, encoding: .utf8)
        try await Fixture.call(Fixture.seerChrome, in: app)
        try await Fixture.call(Fixture.seerWithWallet, in: app)
        try await Fixture.call(Fixture.seerToasts, in: app)

        let derived = folder.appendingPathComponent("DerivedData")
        let mac = try xcodebuild(["-project", "Seer.xcodeproj", "-scheme", "Seer-macOS", "-destination", "platform=macOS", "CODE_SIGNING_ALLOWED=NO",
                                  "-skip-testing:SeerUITests-macOS", "build", "test"], in: app, derived: derived, home: folder.appendingPathComponent("home"))
        XCTAssertEqual(mac.status, 0, Shell.digest(mac.log))
        XCTAssertTrue(mac.log.contains("** TEST SUCCEEDED **"), Shell.digest(mac.log))
        for test in ["aLaunchThatAsksForASheetPutsUpWhatItGoesOver", "aSheetGoesUpOverWhateverIsUpAndClosesAlone", "aSheetIsNotATab",
                     "anAliasOpensWhatItsDestinationOpens", "theGateHoldsOnAPlainLaunchAndOnItsOwnName", "aLaunchThatNamesAnotherDestinationOpensPastTheGate"] {
            XCTAssertTrue(mac.log.contains("Test \(test)() passed"), test)
        }
        XCTAssertFalse(mac.log.contains(": warning: "), "the app builds without a warning: \(mac.log.components(separatedBy: "\n").filter { $0.contains(": warning: ") }.prefix(5))")
        let iOS = try xcodebuild(["-project", "Seer.xcodeproj", "-scheme", "Seer-iOS", "-destination", "generic/platform=iOS Simulator", "build", "build-for-testing"],
                                 in: app, derived: derived)
        XCTAssertEqual(iOS.status, 0, Shell.digest(iOS.log))
        let written = ["ModalHosting.swift", "PlatformNavigationView.swift", "AppDestination.swift", "LayoutService"]
        XCTAssertFalse(iOS.log.components(separatedBy: "\n").contains { line in line.contains(": warning: ") && written.contains { line.contains($0) } },
                       "the toast window and the navigation build for iOS without a warning: \(iOS.log.components(separatedBy: "\n").filter { $0.contains(": warning: ") }.prefix(5))")
        if testRun?.totalFailureCount == 0 { try? FileManager.default.removeItem(at: derived) }
    }

    /// Seer's sheets at their own heights (2026-11-15): Wallet over the middle tab at medium, then large, its page drawing
    /// its own close (`bare`); Profile stacked on it at 0.6 of the screen or large, each with the drag indicator; Settings
    /// on Profile at the large detent alone; `wallet.full` and `profile.full` opening them large; the tab bar's tint; the
    /// Seer page's button putting Wallet up. Built and its tests run on macOS (the heights', the aliases' heights', the
    /// bare sheet's and the stacked launch's among them), built for the iOS simulator, where
    /// `.presentationDetents(_:selection:)` puts each sheet up at its first or the launch's alias's height.
    func testSheetsAtTheirOwnHeightsAMediumOneOverATabAndAFractionOneOnItBuild() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GRANITE_BUILD"] == "1", "set GRANITE_BUILD=1 to build the output")
        let folder = try Fixture.folder()
        let app = folder.appendingPathComponent("Seer")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        try await Fixture.call(Fixture.seerProject, in: app)
        try await Fixture.call(Fixture.account, in: app)
        try await Fixture.call(Fixture.signIn, in: app)
        for page in Fixture.seerPages + [Fixture.seerSettings] { try await Fixture.call(page, in: app) }
        try await Fixture.call(Fixture.seerSheets, in: app)
        try await Fixture.call(Fixture.seerWithWallet, in: app)

        let derived = folder.appendingPathComponent("DerivedData")
        let mac = try xcodebuild(["-project", "Seer.xcodeproj", "-scheme", "Seer-macOS", "-destination", "platform=macOS", "CODE_SIGNING_ALLOWED=NO",
                                  "-skip-testing:SeerUITests-macOS", "build", "test"], in: app, derived: derived, home: folder.appendingPathComponent("home"))
        XCTAssertEqual(mac.status, 0, Shell.digest(mac.log))
        XCTAssertTrue(mac.log.contains("** TEST SUCCEEDED **"), Shell.digest(mac.log))
        for test in ["aSheetRestsAtTheHeightsItsLineNamesAndGoesUpAtTheFirst", "anAliasPutsItsSheetUpAtTheHeightItNames", "aSheetWhosePageDrawsItsOwnCloseGetsNoCloseButton",
                     "aLaunchThatAsksForASheetPutsUpWhatItGoesOver", "aSheetGoesUpOverWhateverIsUpAndClosesAlone", "anAliasOpensWhatItsDestinationOpens"] {
            XCTAssertTrue(mac.log.contains("Test \(test)() passed"), test)
        }
        XCTAssertFalse(mac.log.contains(": warning: "), "the app builds without a warning: \(mac.log.components(separatedBy: "\n").filter { $0.contains(": warning: ") }.prefix(5))")
        let iOS = try xcodebuild(["-project", "Seer.xcodeproj", "-scheme", "Seer-iOS", "-destination", "generic/platform=iOS Simulator", "build", "build-for-testing"],
                                 in: app, derived: derived)
        XCTAssertEqual(iOS.status, 0, Shell.digest(iOS.log))
        let written = ["PlatformNavigationView.swift", "AppDestination.swift", "LayoutService"]
        XCTAssertFalse(iOS.log.components(separatedBy: "\n").contains { line in line.contains(": warning: ") && written.contains { line.contains($0) } },
                       "the sheets' heights build for iOS without a warning: \(iOS.log.components(separatedBy: "\n").filter { $0.contains(": warning: ") }.prefix(5))")
        if testRun?.totalFailureCount == 0 { try? FileManager.default.removeItem(at: derived) }
    }

    /// Seer's pages that move the app made before its navigation (r6b, 2026-11-15): the Seer page putting Wallet up,
    /// Wallet closing itself in its bar, Models putting Profile up and the first-run layer reading the tab that is up,
    /// each made while the project has no layout; then the navigation that names them, its sheets at their own heights
    /// and the first-run layer over the tabs. Built and its tests run on macOS, built for the iOS simulator.
    func testPagesThatMoveTheAppMadeBeforeTheNavigationBuild() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GRANITE_BUILD"] == "1", "set GRANITE_BUILD=1 to build the output")
        let folder = try Fixture.folder()
        let app = folder.appendingPathComponent("Seer")
        try FileManager.default.createDirectory(at: app, withIntermediateDirectories: true)
        for call in [Fixture.seerProject, Fixture.account, Fixture.signIn] + Fixture.seerStill + Fixture.seerMovers { try await Fixture.call(call, in: app) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: app.appendingPathComponent("Services/LayoutService").path), "the pages come first")
        try await Fixture.call(Fixture.seerAfterItsPages, in: app)

        let derived = folder.appendingPathComponent("DerivedData")
        let mac = try xcodebuild(["-project", "Seer.xcodeproj", "-scheme", "Seer-macOS", "-destination", "platform=macOS", "CODE_SIGNING_ALLOWED=NO",
                                  "-skip-testing:SeerUITests-macOS", "build", "test"], in: app, derived: derived, home: folder.appendingPathComponent("home"))
        XCTAssertEqual(mac.status, 0, Shell.digest(mac.log))
        XCTAssertTrue(mac.log.contains("** TEST SUCCEEDED **"), Shell.digest(mac.log))
        for test in ["aSheetGoesUpOverWhateverIsUpAndClosesAlone", "aSheetWhosePageDrawsItsOwnCloseGetsNoCloseButton", "anAliasPutsItsSheetUpAtTheHeightItNames",
                     "aLaunchThatNamesAnotherDestinationOpensPastTheGate"] {
            XCTAssertTrue(mac.log.contains("Test \(test)() passed"), test)
        }
        XCTAssertFalse(mac.log.contains(": warning: "), "the app builds without a warning: \(mac.log.components(separatedBy: "\n").filter { $0.contains(": warning: ") }.prefix(5))")
        let iOS = try xcodebuild(["-project", "Seer.xcodeproj", "-scheme", "Seer-iOS", "-destination", "generic/platform=iOS Simulator", "build", "build-for-testing"],
                                 in: app, derived: derived)
        XCTAssertEqual(iOS.status, 0, Shell.digest(iOS.log))
        let written = ["PlatformNavigationView.swift", "AppDestination.swift", "LayoutService"] + Fixture.seerMovers.map { "Components/\($0.type!)/" }
        XCTAssertFalse(iOS.log.components(separatedBy: "\n").contains { line in line.contains(": warning: ") && written.contains { line.contains($0) } },
                       "the pages and the navigation build for iOS without a warning: \(iOS.log.components(separatedBy: "\n").filter { $0.contains(": warning: ") }.prefix(5))")
        if testRun?.totalFailureCount == 0 { try? FileManager.default.removeItem(at: derived) }
    }

    func testALinkedProjectBuildsOnBothPlatforms() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["GRANITE_BUILD"] == "1", "set GRANITE_BUILD=1 to build the output")
        let folder = try Fixture.folder()
        let project = folder.appendingPathComponent("Greeter")
        try ClassicProject.write(to: project)
        try await Fixture.call(GraniteAppAgent.Input(make: .link), in: project)
        let derived = folder.appendingPathComponent("DerivedData")
        let mac = try xcodebuild(["-project", "Greeter.xcodeproj", "-scheme", "Greeter", "-destination", "platform=macOS", "CODE_SIGNING_ALLOWED=NO", "build", "test"],
                                 in: project, derived: derived, home: folder.appendingPathComponent("home"))
        XCTAssertEqual(mac.status, 0, Shell.digest(mac.log))
        XCTAssertTrue(mac.log.contains("BootTests/bootingMarksTheAppReady()") && mac.log.contains("** TEST SUCCEEDED **"), Shell.digest(mac.log))
        let iOS = try xcodebuild(["-project", "Greeter.xcodeproj", "-scheme", "Greeter", "-destination", "generic/platform=iOS Simulator", "build"],
                                 in: project, derived: derived)
        XCTAssertEqual(iOS.status, 0, Shell.digest(iOS.log))
        if testRun?.totalFailureCount == 0 { try? FileManager.default.removeItem(at: derived) }
    }
}

