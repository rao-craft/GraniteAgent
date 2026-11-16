import CryptoKit
import Foundation
import XCTest
@testable import GraniteAgent

/// PIN: ADDITIVE ONLY. Launch aliases, `over` and the toast window are words a call says; every call that says none of
/// them writes what it wrote before them, byte for byte. Each navigation and modals call below (the guide's examples,
/// each style, sheets, a default, a gate, and the gate taken away) is held to the bytes the agent wrote at 4e59a5e,
/// the commit before those words: a scenario's digest is the SHA-256 of its files' paths and SHA-256s, one a line.
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

    func testEveryCallWithoutTheNewWordsWritesTheBytesItWroteBefore() async throws {
        let recipes = try await Self.recipes(), seer = try await Self.seer()
        var scenarios = Self.scenarios()
        XCTAssertEqual(Set(scenarios.map(\.name)), Set(Self.before.keys))
        scenarios.sort { $0.name < $1.name }
        for scenario in scenarios {
            let folder = try Fixture.folder().appendingPathComponent("app")
            try FileManager.default.copyItem(at: scenario.seer ? seer : recipes, to: folder)
            let result = try await Fixture.call(scenario.input, in: folder)
            let files = try result.paths.sorted().map { path in
                let digest = SHA256.hash(data: try Data(contentsOf: URL(fileURLWithPath: path))).map { String(format: "%02x", $0) }.joined()
                return "\(path.dropFirst(folder.path.count + 1)) \(digest)"
            }
            let digest = SHA256.hash(data: Data(files.joined(separator: "\n").utf8)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(digest, Self.before[scenario.name], "\(scenario.name) wrote other bytes than before:\n" + files.joined(separator: "\n"))
        }
    }

    /// The calls, each made in a copy of the app it needs.
    static func scenarios() -> [(name: String, input: GraniteAppAgent.Input, seer: Bool)] {
        var scenarios: [(name: String, input: GraniteAppAgent.Input, seer: Bool)] = []
        for style in GraniteStyle.allCases {
            var input = Fixture.navigation
            input.style = style
            if style == .split { input.destinations = [#"recipes: RecipeList "Recipes" book | Settings"#, #"search: RecipeSearch "Search" magnifyingglass"#] }
            scenarios.append(("recipes.\(style.rawValue)", input, false))
        }
        var sheet = Fixture.navigation
        sheet.destinations = [#"recipes: RecipeList "Recipes" book"#, #"search: RecipeSearch "Search" magnifyingglass"#, #"settings: Settings "Settings" gearshape sheet"#]
        scenarios.append(("recipes.sheet", sheet, false))
        var preferred = Fixture.navigation
        preferred.destinations = [#"recipes: RecipeList "Recipes" book"#, #"search: RecipeSearch "Search" magnifyingglass default"#]
        scenarios.append(("recipes.default", preferred, false))
        scenarios.append(("recipes.modals", Fixture.modals, false))
        scenarios.append(("seer.gated", Fixture.seerNavigation, true))
        var plain = Fixture.seerNavigation
        plain.gate = nil
        plain.relays = nil
        plain.destinations = plain.destinations?.filter { !$0.hasSuffix(" gate") }
        scenarios.append(("seer.plain", plain, true))
        for style in [GraniteStyle.tabs, .sidebar, .split] {
            var input = Fixture.seerNavigation
            input.style = style
            scenarios.append(("seer.\(style.rawValue)", input, true))
        }
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
}
