import Foundation
@testable import GraniteAgent

enum Fixture {
    /// A folder of its own for one test, removed with the process's temporary files.
    static func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("granite-\(UUID().uuidString.prefix(8))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// One call, as the host makes it, into `folder`.
    @discardableResult
    static func call(_ input: GraniteAppAgent.Input, in folder: URL, model: FakeHostModel? = nil) async throws -> GraniteResult {
        var input = input
        input.directory = folder.path
        return try await GraniteAppAgent.write(input, model: model, note: { _ in }, yield: { _ in })
    }

    /// A recipe app's own value type, as the `models` agent writes one, with the call the app's work makes.
    static let recipe = """
        import Foundation

        /// A dish someone saved.
        struct Recipe: Codable, Hashable, Identifiable, Sendable {
            var id: String
            var title: String
            var summary: String?
            var minutes: Int
            var photo: URL?
            var added: Date

            init(id: String, title: String, summary: String? = nil, minutes: Int = 30, photo: URL? = nil, added: Date) {
                self.id = id
                self.title = title
                self.summary = summary
                self.minutes = minutes
                self.photo = photo
                self.added = added
            }
        }

        extension Recipe {
            /// A recipe to preview and test with.
            static let preview: Recipe = Recipe(id: "recipe-1", title: "Sample title", summary: "Sample summary", minutes: 30, added: Date(timeIntervalSince1970: 1_767_225_600))

            /// One page of recipes, as the app's API would answer it.
            static func page(_ page: Int) async throws -> [Recipe] {
                (0..<10).map { index in
                    Recipe(id: "\\(page)-\\(index)", title: "Recipe \\(page * 10 + index)", minutes: 10 + index, added: Date(timeIntervalSince1970: Double(page * 10 + index)))
                }
            }
        }

        """

    static let project = GraniteAppAgent.Input(make: .project, name: "Recipes", bundleId: "com.example.recipes")

    static let recipesService = GraniteAppAgent.Input(
        make: .service, type: "Recipes",
        state: ["recipes [Recipe] = []", #"favorite String? "the recipe starred last""#, "page Int = 1"],
        events: [#"load(page Int) -> recipes = Recipe.page(page) "loads one page""#, "more(page Int) +> recipes = Recipe.page(page)"],
        persist: true)

    static let recipeList = GraniteAppAgent.Input(
        make: .component, type: "RecipeList", relays: ["recipes: RecipesService"], layout: .list,
        shows: ["items = recipes.state.recipes", #"title = "Recipes""#, #"empty = "No recipes yet""#, "selection = recipes.state.favorite"],
        actions: ["refresh = try await recipes.load(page: 1)", "more = try await recipes.more(page: recipes.state.recipes.count / 10 + 1)",
                  #"favor(recipe Recipe) "Favorite" star = recipes.set(.favorite(recipe.id))"#])

    static let search = GraniteAppAgent.Input(
        make: .component, type: "RecipeSearch", relays: ["recipes: RecipesService"], layout: .search,
        shows: ["items = recipes.state.recipes", #"title = "Search""#, #"empty = "Find a recipe by its name""#],
        actions: ["search(text String) = try await recipes.load(page: 1)"])

    static let navigation = GraniteAppAgent.Input(
        make: .navigation,
        destinations: [#"recipes: RecipeList "Recipes" book"#, #"search: RecipeSearch "Search" magnifyingglass"#, #"settings: Settings "Settings" gearshape"#],
        style: .adaptive)

    static let modals = GraniteAppAgent.Input(make: .modals)

    static let kit = GraniteAppAgent.Input(make: .package, name: "RecipeKit")

    static let pantry = GraniteAppAgent.Input(
        make: .service, type: "Pantry", into: "Packages/RecipeKit",
        state: ["items [String] = []", "checked [String: Bool] = [:]"],
        events: [#"restock(item String) +> items "adds what ran out to the list""#, "empty() -> items = []"],
        notes: "A pantry list: what to buy next.")

    static let grid = GraniteAppAgent.Input(
        make: .component, type: "RecipeGrid", relays: ["recipes: RecipesService"], layout: .grid,
        shows: ["items = recipes.state.recipes", #"title = "Gallery""#],
        actions: ["refresh = try await recipes.load(page: 1)", "open(recipe Recipe) = recipes.set(.favorite(recipe.id))"])

    static let detail = GraniteAppAgent.Input(
        make: .component, type: "RecipeDetail", state: ["let recipe Recipe"], relays: ["recipes: RecipesService"], layout: .detail,
        shows: ["item = recipe", "title = recipe.title"],
        actions: [#"favor(recipe Recipe) "Favorite" star = recipes.set(.favorite(recipe.id))"#,
                  "rate(recipe Recipe, stars Int) = recipes.set(.favorite(recipe.id))",
                  "share(recipe Recipe) = recipes.set(.favorite(recipe.id))"],
        views: [#"header(recipe Recipe, rate (Int) -> Void, share () -> Void) "the photo large, the title and how long it takes""#])

    static let compose = GraniteAppAgent.Input(
        make: .component, type: "NewRecipe", state: [#"title String = """#, #"notes String = """#, "minutes Int = 30"],
        relays: ["recipes: RecipesService"], layout: .compose,
        shows: [#""Title" = state.title"#, #""Notes" = state.notes"#, #""Time/Minutes" = state.minutes"#, #"title = "New Recipe""#],
        actions: [#"submit "Save" = try await recipes.load(page: 1)"#])

    static let tabs = GraniteAppAgent.Input(
        make: .component, type: "Library", layout: .tabs,
        shows: [#""Recipes" = RecipeList()"#, #""Gallery" = RecipeGrid()"#, #"title = "Library""#])

    static let browser = GraniteAppAgent.Input(
        make: .component, type: "RecipeBrowser", relays: ["recipes: RecipesService"], layout: .threePane,
        shows: ["items = recipes.state.recipes", "selection = recipes.state.favorite", #"title = "Browse""#],
        actions: ["refresh = try await recipes.load(page: 1)"])

    static let today = GraniteAppAgent.Input(
        make: .component, type: "Today", relays: ["recipes: RecipesService"], layout: .blank, notes: "today's three newest recipes")

    /// What the host's model answers, in the order the calls above ask: a work body that does not parse and then one
    /// that does, a subview's body, a page's body.
    static func model() -> FakeHostModel {
        FakeHostModel(bodies: [
            "return [item",
            "let trimmed = item.trimmingCharacters(in: .whitespaces)\nguard !trimmed.isEmpty else { throw URLError(.badURL) }\nreturn [trimmed]",
            "VStack(alignment: .leading, spacing: 8) {\n    AsyncImage(url: recipe.photo) { image in\n        image.resizable().scaledToFill()\n    } placeholder: {\n        Color.secondary.opacity(0.15)\n    }\n    .frame(height: 220)\n    .clipShape(RoundedRectangle(cornerRadius: 12))\n    .accessibilityHidden(true)\n    Text(recipe.title)\n        .font(.title.bold())\n    Label(\"\\(recipe.minutes) min\", systemImage: \"clock\")\n        .font(.subheadline)\n        .foregroundStyle(.secondary)\n    HStack(spacing: 16) {\n        Button(\"Rate\") { rate(5) }\n        Button(\"Share\") { share() }\n    }\n}",
            "ScrollView {\n    VStack(alignment: .leading, spacing: 12) {\n        Text(\"Today\")\n            .font(.largeTitle.bold())\n        ForEach(recipes.state.recipes.prefix(3)) { recipe in\n            Text(recipe.title)\n                .font(.headline)\n        }\n    }\n    .padding()\n}",
        ])
    }


    /// Seer's shell (2026-11-15): signed out, Sign In full screen; signed in, three tabs with the middle one where a
    /// plain launch opens, and the other places sheets over them; every place opens from `-destination <name>`.
    static let seerProject = GraniteAppAgent.Input(make: .project, name: "Seer", bundleId: "com.example.seer")

    static let account = GraniteAppAgent.Input(make: .service, type: "Account", state: ["session String?"], persist: true)

    static let signIn = GraniteAppAgent.Input(
        make: .component, type: "SignIn", state: [#"name String = """#], relays: ["account: AccountService"], layout: .compose,
        shows: [#""Name" = state.name"#, #"title = "Sign In""#],
        actions: [#"submit "Sign In" = account.set(.session(state.name))"#])

    /// A page with nothing of its own yet: its name, empty.
    static func placeholderPage(_ type: String, symbol: String) -> GraniteAppAgent.Input {
        GraniteAppAgent.Input(make: .component, type: type, layout: .blank, body: #"ContentUnavailableView("\#(type)", systemImage: "\#(symbol)")"#)
    }

    static let seerPages = [placeholderPage("Library", symbol: "books.vertical"), placeholderPage("Seer", symbol: "sparkles"),
                            placeholderPage("Models", symbol: "cpu"), placeholderPage("Profile", symbol: "person.crop.circle"),
                            placeholderPage("Wallet", symbol: "creditcard")]

    static let seerNavigation = GraniteAppAgent.Input(
        make: .navigation, relays: ["account: AccountService"],
        destinations: [#"auth: SignIn "Sign In" person gate"#, #"library: Library "Library" books.vertical"#, #"seer: Seer "Seer" sparkles default"#,
                       #"models: Models "Models" cpu"#, #"profile: Profile "Profile" person.crop.circle sheet"#, #"wallet: Wallet "Wallet" creditcard sheet"#],
        gate: "account.state.session == nil")

    /// Seer's launch contract (2026-11-15): sub-destinations by alias, the gate's among them; Profile over the Models tab
    /// and Settings stacked on Profile when a launch names them; Wallet over the default tab.
    static let seerShell = GraniteAppAgent.Input(
        make: .navigation, relays: ["account: AccountService"],
        destinations: [#"auth: SignIn "Sign In" person gate"#, #"library: Library "Library" books.vertical.fill"#, #"seer: Seer "Seer" sparkles default"#,
                       #"models: Models "Models" externaldrive.fill.badge.person.crop"#, #"profile: Profile "Profile" person.crop.circle sheet over models"#,
                       #"settings: Settings "Settings" gearshape sheet over profile"#, #"wallet: Wallet "Wallet" creditcard sheet"#,
                       "auth.signup -> auth", "auth.code -> auth", "void.reply -> seer", "settings.feedback -> settings", "model.edit -> models"],
        gate: "account.state.session == nil")

    /// The page Settings goes up in, for the shell above.
    static let seerSettings = placeholderPage("Settings", symbol: "gearshape")

    /// Seer's sheets at their own heights (2026-11-15), as the original's are: Wallet over the middle tab at medium,
    /// then large; Profile stacked on it at 0.6 of the screen, each showing the drag indicator; Settings on Profile at
    /// the large detent alone, its line naming none.
    static let seerDetents = GraniteAppAgent.Input(
        make: .navigation, relays: ["account: AccountService"],
        destinations: [#"auth: SignIn "Sign In" person gate"#, #"library: Library "Library" books.vertical"#, #"seer: Seer "Seer" sparkles default"#,
                       #"models: Models "Models" cpu"#, #"wallet: Wallet "Wallet" creditcard sheet over seer detents medium large"#,
                       #"profile: Profile "Profile" person.crop.circle sheet over wallet detents fraction(0.6)"#,
                       #"settings: Settings "Settings" gearshape sheet over profile"#],
        gate: "account.state.session == nil")

    /// Seer's toasts, in a window of their own one level above alerts, their text in the serif design as its type is.
    static let seerToasts = GraniteAppAgent.Input(make: .modals, toasts: .window, toastDesign: .serif)

    /// Seer's shell as the original draws it (Components/Main/MainView.swift): the tabs' images alone, the mark drawn as
    /// the middle tab's image at 30, the accent on the selected tab, a light impact on a tab change, and the first-run
    /// layer over the tabs.
    static var seerChrome: GraniteAppAgent.Input {
        var input = seerShell
        input.destinations = input.destinations?.map {
            $0.replacingOccurrences(of: #""Seer" sparkles default"#, with: #""Seer" SeerMark().frame(width: 30, height: 30) default"#)
        }
        input.tabBar = .icons
        input.tint = "Color.accentColor"
        input.tabFeedback = .light
        input.overlays = ["Onboarding"]
        return input
    }

    /// The first-run layer the shell draws over the tabs, for the call above.
    static let seerOnboarding = placeholderPage("Onboarding", symbol: "hand.wave")

    /// A stand-in for the app's mark, drawn in code, for the call above: a disc with a bright bezel.
    static let seerMark = """
        import SwiftUI

        /// A stand-in for the app's mark, drawn in code: a disc with a bright bezel.
        struct SeerMark: View {
            var body: some View {
                Circle()
                    .fill(.gray)
                    .overlay(Circle().inset(by: 4).fill(.white.opacity(0.35)))
            }
        }

        """

    /// The Seer page again, once the navigation is there, with a button that puts the wallet up.
    static let seerWithWallet = GraniteAppAgent.Input(
        make: .component, type: "Seer", relays: ["layout: LayoutService"], layout: .blank,
        actions: [#"wallet "Wallet" creditcard = layout.present(.wallet)"#],
        body: #"ContentUnavailableView("Seer", systemImage: "sparkles")"#)

    static let settings = GraniteAppAgent.Input(

        make: .component, type: "Settings", relays: ["config: ConfigService"], layout: .settings,
        shows: [#""Appearance/Theme" = config.state.appearance"#, #""Usage/Launches" = config.state.launches"#, #""Usage/Last opened" = config.state.lastOpened"#],
        actions: [#"restore "Restore Defaults" = config.set(.reset)"#])
}
