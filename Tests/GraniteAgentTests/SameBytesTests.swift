import CryptoKit
import Foundation
import XCTest
@testable import GraniteAgent

/// PIN: ADDITIVE ONLY. Launch aliases, `over`, the toast window, a sheet's `detents`, `bare` and an alias's height are
/// words a call says; every call that says none of them writes what it wrote before them, byte for byte. Each
/// navigation and modals call in `before` (the guide's examples, each style, sheets, a default, a gate, and the gate
/// taken away) is held to the bytes the agent wrote at 4e59a5e, the commit before the first of those words; each in
/// `beforeDetents` (Seer's launch contract, its shell as the original draws it, its toasts in their own window) to the
/// bytes of 9b5bc8f, the commit before `detents`; each in `beforeBare` (Seer's sheets at their own heights) to the bytes
/// of f82e0f7, the commit before `bare` and an alias's height. A scenario's digest is the SHA-256 of its files' paths
/// and SHA-256s, one a line.
final class SameBytesTests: XCTestCase {
    static let before: [String: String] = [
        "recipes.adaptive": "83bb25e1ed00cb1a3d6d5ad2f6193b5ab87302ab38d88a91005a8f673d572417",
        "recipes.tabs": "895f4e487aa451ec37b23af41ce1857bb7c8f54568b36c60538d3989b1d0fe73",
        "recipes.sidebar": "45a58376dec74e453e5590b11e9f2938cc909a9b65d168f665150830d5415c8d",
        "recipes.split": "250fa3910feb5fb200f7faad1f66370d8f4259d5ff950145ccad1f66d39dac18",
        "recipes.sheet": "458a908ec118f38ce47da53cb9898524bbabfea5cf8d0ad4d0472611f3c4323f",
        "recipes.default": "08afcd31093160d0b175ee13abe9912760939befaafbb552a364fb39bff31900",
        "recipes.modals": "d2bac2538679358a07fd95a61f921ed0ade36c6ac31f5d0e86aa038692edf394",
        "seer.gated": "5832188da7a6dc25460c07292e441114587a6a35a79360f2f99429f4371cb28c",
        "seer.plain": "70ec7747f2b9cfae5b77855a0dea7b9e7e22605583d0a9f66465e5d048e38d46",
        "seer.tabs": "d05b91e05dd35c7c211573d8473cade3fc9fab8e89370c734c22c0e8dff30899",
        "seer.sidebar": "f5b3cfaf990e211eaea7fe1f0dd7e38fb63bbc7d2a1f528b87e5e3d2445cc5d0",
        "seer.split": "0235b6b8ba98d9aab3ced78975895c26f98cb54150e14ef2ff201c832fc9ed04",
    ]

    /// Calls that say the words of a2e0f28 and 9b5bc8f and no `detents`, held to the bytes of 9b5bc8f.
    static let beforeDetents: [String: String] = [
        "seer.shell": "68dcbd9190e7db4c24fc5666279cbd6eca7989b2a4c9baee301c6905b78612e7",
        "seer.chrome": "01e26324e167fe27c8236aa265c489e8568561cf2cd8aaf39300e1e10b1484f9",
        "seer.toasts": "987ff00e234d87a550fbe99988192a2187ed74863ede624031ee879f0ac6dc5b",
    ]

    /// Calls that say `detents` and none of the words after it, held to the bytes of f82e0f7.
    static let beforeBare: [String: String] = [
        "seer.detents": "aedd1999133d3bbadb64538e3e4b65cee332d12bfc4dc96480176b8e1161582f",
    ]

    func testEveryCallWithoutTheNewWordsWritesTheBytesItWroteBefore() async throws {
        let recipes = try await Self.recipes(), seer = try await Self.seer(), shell = try await Self.seerShell()
        let pinned = Self.before.merging(Self.beforeDetents) { first, _ in first }.merging(Self.beforeBare) { first, _ in first }
        var scenarios = Self.scenarios()
        XCTAssertEqual(Set(scenarios.map(\.name)), Set(pinned.keys))
        XCTAssertEqual(pinned.count, Self.before.count + Self.beforeDetents.count + Self.beforeBare.count, "a scenario is pinned once")
        scenarios.sort { $0.name < $1.name }
        for scenario in scenarios {
            let folder = try Fixture.folder().appendingPathComponent("app")
            let app = switch scenario.app {
            case .recipes: recipes
            case .seer: seer
            case .seerShell: shell
            }
            try FileManager.default.copyItem(at: app, to: folder)
            let result = try await Fixture.call(scenario.input, in: folder)
            let files = try result.paths.sorted().map { path in
                let digest = SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: path))).map { String(format: "%02x", $0) }.joined()
                return "\(path.dropFirst(folder.path.count + 1)) \(digest)"
            }
            let digest = SHA256.hash(data: Data(files.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, pinned[scenario.name], "\(scenario.name) wrote other bytes than before:\n" + files.joined(separator: "\n"))
        }
    }

    /// The app a call is made in a copy of.
    enum App { case recipes, seer, seerShell }

    /// The calls, each made in a copy of the app it needs.
    static func scenarios() -> [(name: String, input: GraniteAppAgent.Input, app: App)] {
        var scenarios: [(name: String, input: GraniteAppAgent.Input, app: App)] = []
        for style in GraniteStyle.allCases {
            var input = Fixture.navigation
            input.style = style
            if style == .split { input.destinations = [#"recipes: RecipeList "Recipes" book | Settings"#, #"search: RecipeSearch "Search" magnifyingglass"#] }
            scenarios.append(("recipes.\(style.rawValue)", input, .recipes))
        }
        var sheet = Fixture.navigation
        sheet.destinations = [#"recipes: RecipeList "Recipes" book"#, #"search: RecipeSearch "Search" magnifyingglass"#, #"settings: Settings "Settings" gearshape sheet"#]
        scenarios.append(("recipes.sheet", sheet, .recipes))
        var preferred = Fixture.navigation
        preferred.destinations = [#"recipes: RecipeList "Recipes" book"#, #"search: RecipeSearch "Search" magnifyingglass default"#]
        scenarios.append(("recipes.default", preferred, .recipes))
        scenarios.append(("recipes.modals", Fixture.modals, .recipes))
        scenarios.append(("seer.gated", Fixture.seerNavigation, .seer))
        var plain = Fixture.seerNavigation
        plain.gate = nil
        plain.relays = nil
        plain.destinations = plain.destinations?.filter { !$0.hasSuffix(" gate") }
        scenarios.append(("seer.plain", plain, .seer))
        for style in [GraniteStyle.tabs, .sidebar, .split] {
            var input = Fixture.seerNavigation
            input.style = style
            scenarios.append(("seer.\(style.rawValue)", input, .seer))
        }
        scenarios.append(("seer.shell", Fixture.seerShell, .seerShell))
        scenarios.append(("seer.chrome", Fixture.seerChrome, .seerShell))
        scenarios.append(("seer.toasts", Fixture.seerToasts, .seerShell))
        scenarios.append(("seer.detents", Fixture.seerDetents, .seerShell))
        return scenarios
    }

    /// The recipe app with its three pages, before navigation.
    static func recipes() async throws -> URL {
        let folder = try Fixture.folder()
        try await Fixture.call(Fixture.project, in: folder)
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Shared/Models"), withIntermediateDirectories: true)
        try Fixture.recipe.write(to: folder.appendingPathComponent("Shared/Models/Recipe.swift"), atomically: true, encoding: .utf8)
        try await Fixture.call(Fixture.recipesService, in: folder)
        for page in [Fixture.recipeList, Fixture.search, Fixture.settings] { try await Fixture.call(page, in: folder) }
        return folder
    }

    /// Seer with its account service, Sign In and its placeholder pages, before navigation.
    static func seer() async throws -> URL {
        let folder = try Fixture.folder()
        try await Fixture.call(Fixture.seerProject, in: folder)
        try await Fixture.call(Fixture.account, in: folder)
        try await Fixture.call(Fixture.signIn, in: folder)
        for page in Fixture.seerPages { try await Fixture.call(page, in: folder) }
        return folder
    }

    /// Seer as above with Settings, the first-run layer and a stand-in mark: what its shell's calls name.
    static func seerShell() async throws -> URL {
        let folder = try await seer()
        for page in [Fixture.seerSettings, Fixture.seerOnboarding] { try await Fixture.call(page, in: folder) }
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("Shared/Views"), withIntermediateDirectories: true)
        try Fixture.seerMark.write(to: folder.appendingPathComponent("Shared/Views/SeerMark.swift"), atomically: true, encoding: .utf8)
        return folder
    }
}
