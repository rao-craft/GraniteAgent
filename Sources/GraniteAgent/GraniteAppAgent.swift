//  WHAT: Everything Granite-specific an iOS + macOS app needs, as a Granite agent package: a new project, Granite
//        brought into an existing one, a kit of services, a service in the skill's single-writer shape with its
//        tests, a page laid out from what it shows and does, the app's navigation, and its modals. One call makes
//        one of them, from compact lines a local model writes in one tool call, and answers the files it wrote.
//  IN:   Input: `make` and the lines that make needs (state, events, relays, shows, actions, views, destinations…).
//  OUT:  GraniteResult: every file written or edited, the types, and a sentence for each decision.
//  PIN:  THE AGENT HOLDS THE QUALITY. Every file is made from the lines; the host's model is asked only for what is
//        the app's own (a unit of work no expression says, a subview's body a line describes), and its Swift is
//        parsed before it lands. A call that cannot be honoured is refused with every reason, and nothing is written.
//  PIN:  ONE CALL AT A TIME (`lanes` 1). Calls edit files several makes share (the project file, the root that
//        holds the relays), so a second call waits for the first.

import Foundation
import GraniteAgents

public struct GraniteAppAgent: GraniteAgentPackage {
    public struct Input: Codable, Sendable {
        /// What to make.
        public var make: GraniteMake
        /// The app's or the kit's name: `Recipes`.
        public var name: String?
        /// The app's bundle identifier; `com.example.<name>` when left out.
        public var bundleId: String?
        /// The Apple team the app signs with.
        public var team: String?
        /// The lowest OS each app runs on, one a line: `iOS 26`, `macOS 26`; iOS 17 and macOS 14 when left out.
        public var platforms: [String]?
        /// The service (`Feed` is `FeedService`) or the page (`Feed`) to make.
        public var type: String?
        /// The folder the files go in, relative to the host's.
        public var into: String?
        /// A service's or a page's fields, one a line, in the models syntax: `posts [Post] = []`.
        public var state: [String]?
        /// A service's work, one a line: `load(page Int) -> posts = API.posts(page: page)`.
        public var events: [String]?
        /// The services a service's work, a page or navigation's gate reads: `feed: FeedService`.
        public var relays: [String]?
        /// How a page draws what it shows.
        public var layout: GraniteLayout?
        /// What a page draws: `items = feed.state.posts`, `"Theme" = config.state.appearance`.
        public var shows: [String]?
        /// What a page does: `refresh = try await feed.load(page: 1)`.
        public var actions: [String]?
        /// A page's subviews: `row(post Post) "title, author and score"`.
        public var views: [String]?
        /// A blank page's body as Swift, written as given (parse-checked) instead of asked of the host's model: the
        /// view the app already has, filled from the relays and actions.
        public var body: String?
        /// The app's destinations: `feed: Feed "Feed" house`, and after the symbol `default`, `sheet` (`over` a tab or a
        /// sheet, `detents` and its heights, `bare` for a page that draws its own close) or `gate`; a launch alias
        /// `auth.signup -> auth`, with a height its sheet opens at (`world.full -> world large`).
        public var destinations: [String]?
        /// What holds navigation's gate, as a Swift condition over a relay's state: `account.state.session == nil`.
        public var gate: String?
        /// How the app moves between its destinations.
        public var style: GraniteStyle?
        /// What a tab bar item shows: its image over its title, or its image alone.
        public var tabBar: GraniteTabBar?
        /// The colour the tab bar's selected item takes, a Swift expression: `Color.accent`.
        public var tint: String?
        /// The impact a person feels when the tab changes.
        public var tabFeedback: GraniteFeedback?
        /// Views drawn over the tabs, bottom to top, under every sheet: a first-run layer, `Onboarding`.
        public var overlays: [String]?
        /// Where modals shows its toasts: over the root view, or on iOS in a window of their own above alerts.
        public var toasts: GraniteToasts?
        /// The font design of the toasts' text in their own window: serif, rounded or monospaced.
        public var toastDesign: GraniteToastDesign?
        /// The root page; `Home` when left out.
        public var root: String?
        /// Remote packages the app links, pinned: `https://github.com/kean/Nuke@<revision> Nuke NukeUI`.
        public var packages: [String]?
        /// Modules a service's or a page's files import beside Foundation, SwiftUI and Granite.
        public var imports: [String]?
        /// Whether a service's state is kept between launches.
        public var persist: Bool?
        /// What the work or the page is for: what the host's model writes bodies from.
        public var notes: String?
        /// How many times the host's model may answer one body; 3 when left out.
        public var rounds: Int?
        /// The host's folder.
        public var directory: String?

        public init(make: GraniteMake, name: String? = nil, bundleId: String? = nil, team: String? = nil, platforms: [String]? = nil, type: String? = nil,
                    into: String? = nil, state: [String]? = nil, events: [String]? = nil, relays: [String]? = nil,
                    layout: GraniteLayout? = nil, shows: [String]? = nil, actions: [String]? = nil, views: [String]? = nil,
                    body: String? = nil, destinations: [String]? = nil, gate: String? = nil, style: GraniteStyle? = nil,
                    tabBar: GraniteTabBar? = nil, tint: String? = nil, tabFeedback: GraniteFeedback? = nil, overlays: [String]? = nil, toasts: GraniteToasts? = nil, toastDesign: GraniteToastDesign? = nil,
                    root: String? = nil, packages: [String]? = nil, imports: [String]? = nil, persist: Bool? = nil, notes: String? = nil,
                    rounds: Int? = nil, directory: String? = nil) {
            self.make = make; self.name = name; self.bundleId = bundleId; self.team = team; self.platforms = platforms; self.type = type; self.into = into
            self.state = state; self.events = events; self.relays = relays; self.layout = layout; self.shows = shows; self.body = body
            self.actions = actions; self.views = views; self.destinations = destinations; self.gate = gate; self.style = style
            self.tabBar = tabBar; self.tint = tint; self.tabFeedback = tabFeedback; self.overlays = overlays; self.toasts = toasts; self.toastDesign = toastDesign
            self.root = root
            self.packages = packages; self.imports = imports; self.persist = persist; self.notes = notes; self.rounds = rounds
            self.directory = directory
        }

        private enum CodingKeys: String, CodingKey, CaseIterable {
            case make, name, bundleId, team, platforms, type, into, state, events, relays, layout, shows, actions, views, body, destinations
            case gate, style, tabBar, tint, tabFeedback, overlays, toasts, toastDesign, root, packages, imports, persist, notes, rounds, directory
        }

        /// Any key a call carries, to find the ones that are not fields.
        private struct AnyKey: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { nil }
        }

        /// Fields a call writes under another agent's or another word's name, and where each belongs here.
        static let misnamed: [String: String] = [
            "endpoints": "events", "endpoint": "events", "reducers": "events", "work": "events", "methods": "events",
            "fields": "state", "properties": "state", "entities": "state",
            "routes": "destinations", "tabs": "destinations", "sheets": "destinations", "default": "destinations", "condition": "gate",
            "aliases": "destinations", "over": "destinations", "detents": "destinations", "bare": "destinations", "toast": "toasts", "toastFont": "toastDesign",
            "overlay": "overlays", "layers": "overlays", "tabLabels": "tabBar", "tabTitles": "tabBar", "tabHaptics": "tabFeedback",
            "subviews": "views", "rows": "shows", "items": "shows",
            "bundle": "bundleId", "bundleID": "bundleId", "folder": "into", "path": "into", "kind": "make",
            "deploymentTarget": "platforms", "deployment": "platforms", "minimumOS": "platforms",
        ]

        /// PIN: a field granite does not take is refused, never dropped. A service whose events came as `endpoints` (the
        /// network agent's word) was written with no events and reported as written, and every page that called its work
        /// was then refused for a `load` the call had meant to make (Margin c5, 2026-11-02).
        ///
        /// A list may come as one JSON-encoded string (`"[\"load(page Int) -> …\"]"`), as local models write it.
        public init(from decoder: Decoder) throws {
            let any = try decoder.container(keyedBy: AnyKey.self)
            let known = Set(CodingKeys.allCases.map(\.rawValue))
            let unknown = any.allKeys.map(\.stringValue).filter { !known.contains($0) }.sorted()
            if !unknown.isEmpty {
                throw GraniteError.refused(unknown.map { key in
                    "`\(key)` is not one of granite's fields" + (Self.misnamed[key].map { "; what it holds goes in `\($0)`" }
                        ?? " (" + CodingKeys.allCases.map(\.rawValue).filter { $0 != "directory" }.joined(separator: ", ") + ")")
                })
            }
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // `contains`, not `decodeIfPresent`: the schema a model is shown is read through this init, and its
            // decoder holds every key, so `make` stays required there.
            make = c.contains(.make) ? try c.decode(GraniteMake.self, forKey: .make) : try Self.make(by: Set(any.allKeys.map(\.stringValue)))
            name = try c.decodeIfPresent(String.self, forKey: .name)
            bundleId = try c.decodeIfPresent(String.self, forKey: .bundleId)
            team = try c.decodeIfPresent(String.self, forKey: .team)
            platforms = try Self.lines(c, .platforms)
            type = try c.decodeIfPresent(String.self, forKey: .type)
            into = try c.decodeIfPresent(String.self, forKey: .into)
            state = try Self.lines(c, .state)
            events = try Self.lines(c, .events)
            relays = try Self.lines(c, .relays)
            layout = try c.decodeIfPresent(GraniteLayout.self, forKey: .layout)
            shows = try Self.lines(c, .shows)
            actions = try Self.lines(c, .actions)
            views = try Self.lines(c, .views)
            body = try c.decodeIfPresent(String.self, forKey: .body)
            destinations = try Self.lines(c, .destinations)
            gate = try c.decodeIfPresent(String.self, forKey: .gate)
            style = try c.decodeIfPresent(GraniteStyle.self, forKey: .style)
            tabBar = try c.decodeIfPresent(GraniteTabBar.self, forKey: .tabBar)
            tint = try c.decodeIfPresent(String.self, forKey: .tint)
            tabFeedback = try c.decodeIfPresent(GraniteFeedback.self, forKey: .tabFeedback)
            overlays = try Self.lines(c, .overlays)
            toasts = try c.decodeIfPresent(GraniteToasts.self, forKey: .toasts)
            toastDesign = try c.decodeIfPresent(GraniteToastDesign.self, forKey: .toastDesign)
            root = try c.decodeIfPresent(String.self, forKey: .root)
            packages = try Self.lines(c, .packages)
            imports = try Self.lines(c, .imports)
            persist = try c.decodeIfPresent(Bool.self, forKey: .persist)
            notes = try c.decodeIfPresent(String.self, forKey: .notes)
            rounds = try c.decodeIfPresent(Int.self, forKey: .rounds)
            directory = try c.decodeIfPresent(String.self, forKey: .directory)
        }

        /// What a call with no `make` makes, read from the fields only that make takes; refused in words when they
        /// do not say.
        ///
        /// PIN: A MISSING `make` IS READ FROM THE CALL (Seer R4, 2026-11-15). A local model writes a call's fields in the
        /// order its spec lists them, alphabetically, and on every page it skipped `make`, which falls between `layout`
        /// and `relays`. Told `DecodingError.keyNotFound`, it sent the same call six times until the repeat guard closed
        /// the pages. The other fields already say it: only navigation has destinations, only a service has events,
        /// only a page has a layout, shows, actions, views or a body.
        static func make(by keys: Set<String>) throws -> GraniteMake {
            if !keys.isDisjoint(with: ["destinations", "tabBar", "tabFeedback", "overlays"]) { return .navigation }
            if !keys.isDisjoint(with: ["toasts", "toastDesign"]) { return .modals }
            if keys.contains("events") { return .service }
            if !keys.isDisjoint(with: ["layout", "shows", "actions", "views", "body"]) { return .component }
            if !keys.isDisjoint(with: ["bundleId", "team", "platforms"]) { return .project }
            throw GraniteError.refused(["the call has no `make`: add what it makes, one of "
                + GraniteMake.allCases.map { "`\($0.rawValue)`" }.joined(separator: ", ")])
        }

        /// A list of lines: an array, or one string holding a JSON array of strings.
        private static func lines(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) throws -> [String]? {
            if let list = try? c.decodeIfPresent([String].self, forKey: key) { return list }
            guard let text = try c.decodeIfPresent(String.self, forKey: key) else { return nil }
            if let data = text.data(using: .utf8), let list = try? JSONDecoder().decode([String].self, from: data) { return list }
            return [text]
        }
    }

    public typealias Event = GraniteFrame
    public typealias Output = GraniteResult
    public typealias Compute = Void

    public static let word = "granite"
    public static let summary = "makes and grows an iOS + macOS app on Granite — the Xcode project, Granite linked into an existing one, kits, services with their reducers and tests, pages laid out from what they show, navigation and modals."
    public static let lanes: Int? = 1
    /// What it makes, each kind with where it lands: what a host routes to it, and what its answer measures.
    public static let makes = [
        AgentMake(kind: "project", what: "an iOS and macOS app on Granite: its Xcode project, the root that boots it, its environment and settings services and its Home page",
                  into: ["*.xcodeproj", "Shared/App.swift", "Shared/AppDelegate.swift", "Shared/Assets.xcassets/*", "Shared/Utility/AppRoot.swift",
                         "Services/EnvironmentService/*", "Services/ConfigService/*", "Components/Home/*", "Tests/*", "UITests/*"],
                  never: "an API's client or the app's value types"),
        AgentMake(kind: "kit", what: "a Swift package of the app's own, linked into it, for public services", into: ["Packages/*"]),
        AgentMake(kind: "service", what: "a service: its state, its one writer, the work its reducers run, and its tests",
                  into: ["Services/*", "Packages/*/Sources/*/Services/*", "Tests/*OpsTests.swift"]),
        AgentMake(kind: "page", what: "a page that composes the app's views and reads its services; a view the app already has (a kit's FeedView) is shown by a blank page, never rewritten",
                  into: ["Components/*"], never: "the views a page shows"),
        AgentMake(kind: "navigation", what: "the app's destinations and how it moves between them: tabs on iPhone, a sidebar on iPad and the Mac",
                  into: ["Shared/Utility/AppDestination.swift", "Shared/Utility/Routes.swift", "Shared/Utility/Device.swift", "Services/LayoutService/*",
                         "iOS/PlatformNavigationView.swift", "macOS/PlatformNavigationView.swift"]),
        AgentMake(kind: "modals", what: "the app's sheets, alerts, toasts and travelling panels, from one service", into: ["Services/ModalService/*"]),
    ]
    public static let fields = [
        "make": "what to make: project (a new iOS + macOS app), package (a kit of services), link (Granite into an Xcode project this agent did not make), service, component (a page), navigation, modals",
        "name": "the app's or the kit's name, letters and digits, like `Recipes`: project and package",
        "bundleId": "the app's bundle identifier; com.example.<name> when left out: project",
        "team": "the 10-character Apple team id the app signs with: project",
        "platforms": "the lowest OS each app runs on, one a line: `iOS 26`, `macOS 26`; iOS 17 and macOS 14 when left out: project",
        "type": "the service (`Feed` makes FeedService) or the page (`Feed`) to make",
        "into": "the folder, relative to the project; Services/<Type> or Components/<Type> when left out; a kit's folder (`Packages/RecipeKit`) puts a public service in the kit",
        "state": "fields, one a line, in the models syntax: `posts [Post] = []`, `selected String?`; a page's `let post Post` is an input it is made with",
        "events": "a service's work, one a line: `load(page Int) -> posts = API.posts(page: page) \"loads a page\"`; `+> posts` appends; with no `= call` the host's model writes the work",
        "relays": "the services a service's work calls, a page reads, or navigation's `gate` reads: `feed: FeedService` or `Feed`",
        "layout": "how a page draws: list, grid, detail, form, settings, search, compose, tabs, threePane, blank",
        "shows": "what a page draws: `items = feed.state.posts`, `item = …`, `selection = feed.state.selected`, `title = \"Feed\"`, `empty = \"No posts yet\"`; a row of a form `\"Section/Label\" = config.state.field`",
        "actions": "what a page does: `refresh = try await feed.load(page: 1)`, `more = …`, `open(post Post) = …`, `compose \"New Post\" square.and.pencil = …`",
        "views": "a page's subviews: `row(post Post, vote (Bool) -> Void) \"title, author and score, with a vote\"`; a closure is an action the view sends up with `bubble`, routed by the page to the action of its name; a description is what the host's model writes the body from",
        "destinations": "the app's places, one a line: `feed: Feed \"Feed\" house`, or in the symbol's place a view the app has drawn as the tab's image (`seer: Seer \"Seer\" SeerMark().frame(width: 30, height: 30)`); after the symbol, `default` opens the app on it (else the first), `sheet` puts it in a sheet over the tabs (`layout.present(.wallet)`), `sheet over models` or `sheet over profile` a sheet a launch naming it puts up over that tab, or stacked on that sheet, `sheet over seer detents medium large` a sheet at those heights (`medium`, `large`, `fraction(0.6)`, `height(320)`), up at the first with its drag indicator showing (with none, large alone), `bare` after a sheet for a page that draws its own close (the sheet adds none), `gate` shows it instead of the tabs while `gate` holds; `| Detail` names the view beside it in the split style. A line `auth.signup -> auth` is a launch alias, any name with dots: `-destination auth.signup` opens what `-destination auth` opens (the gate's alias holds the gate, any other opens past it) and stays readable in the `destination` default; after the destination an alias may name a height its sheet rests at, which a launch with it puts the sheet up at (`world.full -> world large`)",
        "gate": "navigation's gate: a Swift condition over a relay's state, the relay named in `relays` (`account.state.session == nil`, `account: AccountService`); while it holds, the destination marked `gate` is shown full screen instead of the tabs, and a launch with `-destination <another>` opens past it",
        "style": "how the app moves between destinations: adaptive (tabs on iPhone, a sidebar on iPad and Mac), tabs, sidebar, split",
        "tabBar": "what a tab bar item shows: labels (its image over its title; when left out) or icons (its image alone, an empty title, as `Tab(\"\", …)`)",
        "tint": "the colour of the tab bar's selected item, a Swift colour: `Color.accent`; the app's accent colour when left out",
        "tabFeedback": "the impact felt when the tab changes on iPhone: light, medium, heavy, soft, rigid; none when left out",
        "overlays": "views navigation draws over the tabs, bottom to top, under every sheet: a page the app has, `Onboarding` (a first-run layer that takes touches only where it draws)",
        "toasts": "where modals shows its toasts: overlay (over the root view; when left out) or window (on iOS in a window of their own one level above alerts, `.alert + 1`, over every sheet and alert, a touch elsewhere passing through, the styles in circle symbols; the Mac keeps the overlay)",
        "toastDesign": "the font design of the toasts' text in their own window, with `toasts: window`: serif, rounded or monospaced; the system's when left out",
        "root": "the root page; Home when left out",
        "packages": "remote packages the app links, pinned: `https://github.com/kean/Nuke@<40-hex revision> Nuke NukeUI`",
        "imports": "modules the files import beside Foundation, SwiftUI and Granite; a local package's are found on their own",
        "persist": "whether a service's state is kept between launches",
        "body": "a blank page's body as Swift, written as given: the view the app has, filled from the page's relays and actions (`FeedView(posts: feed.state.posts, actions: …)`)",
        "notes": "what the work or the page is for, in a sentence: what the host's model writes bodies from",
        "rounds": "how many answers the host's model may give one body before the call is refused; 3 when left out",
    ]
    public static let guide = #"""
        Tag granite for an app's architecture on Granite: the project, its services, its pages, how it navigates and its modals. One call makes one thing, and a turn makes only what its request asks for: `project` once, when there is no app yet; services before the pages that read them; navigation once the pages exist. An app it made already has its project, root and boot, so never call `project` or `link` there again. Each call reads the project as it is, so a page binds to a service's real fields; a call it cannot honour is refused with every reason and nothing is written: fix the lines and call again.

        project: {"make": "project", "name": "Recipes", "bundleId": "com.example.recipes"} writes Recipes.xcodeproj (iOS and macOS apps, unit and UI tests, Granite pinned), the root that boots the app, the environment and settings services, and the Home page. `packages` adds pinned remote packages.

        service: {"make": "service", "type": "Recipes", "state": ["recipes [Recipe] = []", "favorite String?"], "events": ["load(page Int) -> recipes = RecipeAPI.page(page) \"loads a page\"", "more(page Int) +> recipes = RecipeAPI.page(page)", "favor(recipe Recipe) = RecipeAPI.favor(recipe.id)"], "persist": true} writes RecipesService. A state line is the models syntax (`name Type = default`, `?` optional). An event is `verb(param Type) -> field = call`: the call is async and throwing (the agent adds try await), `-> field` replaces the field with its result, `+> field` appends a page to a list, and with no `= call` the host's model writes the work from `notes`. `relays` are services the work calls (`catalog: CatalogService`), never one that calls back. A page then calls `try await recipes.load(page: 1)` (it answers the result), writes a field with `recipes.set(.favorite(id))` and binds one with `recipes.binding(\.favorite) { .favorite($0) }`.

        component: {"make": "component", "type": "RecipeList", "layout": "list", "relays": ["recipes: RecipesService"], "shows": ["items = recipes.state.recipes", "title = \"Recipes\"", "empty = \"No recipes yet\""], "actions": ["refresh = try await recipes.load(page: 1)", "more = try await recipes.more(page: 2)", "open(recipe Recipe) = recipes.set(.favorite(recipe.id))", "favor(recipe Recipe) \"Favorite\" star = try await recipes.favor(recipe: recipe)"], "views": ["row(recipe Recipe, favor () -> Void) \"photo, title and minutes, with a heart\""]} writes the page. Layouts: list, grid and search show `items` (search adds `query`); detail shows `item`; threePane shows `items` and `selection`, and a `sidebar`; form, settings and compose show rows `"Section/Label" = recipes.state.field` or `= state.field`, each a control by its type; tabs shows `"Title" = SomeView()` a tab; blank is written by the host's model: a page that shows a view the app already has (a kit's `FeedView(…)`) is `layout: blank` with its relays and actions, and either the body itself in `body` (written as given) or the view and how to fill it named in `notes`. Actions named refresh, more, open, submit and search do what they say; one that takes an item sits in its row's menu; the others are toolbar buttons (`name "Words" sf.symbol = statements`). A view's closure is an action it sends up with `bubble`; the page routes it, where it draws the view, to the action of its name. The page's own state is `state` lines (`query String = ""`); `let recipe Recipe` is an input it is made with.

        navigation: {"make": "navigation", "destinations": ["recipes: RecipeList \"Recipes\" book", "search: RecipeSearch \"Search\" magnifyingglass", "settings: Settings \"Settings\" gearshape"], "style": "adaptive"} writes the destinations, tabs on iPhone and a sidebar on iPad and the Mac, a layout service, routes and Device, and shows them once the app is ready. The pages must exist first. After a symbol, `default` opens the app on that destination, `sheet` puts it in a sheet over the tabs (a page opens it with `layout.present(.settings)`), and `gate` shows it instead of the tabs while the `gate` condition holds: `"gate": "account.state.session == nil"` with `"relays": ["account: AccountService"]`. A sheet line may end `sheet over models` (a launch that names it selects that tab first) or `sheet over profile` (it goes up stacked on that sheet); in use a sheet goes up over whatever is up. After the sheet, `detents medium large`, `detents fraction(0.6)` or `detents height(320) large` are the heights it rests at: it goes up at the first, a launch's too, with its drag indicator showing; a sheet with none goes up large. `bare` after a sheet leaves its close to the page, which draws its own in its bar. An alias may end with a height its sheet rests at (`world.full -> world large`): a launch with it puts the sheet up at that height, once. A line `auth.signup -> auth` is a launch alias: `-destination auth.signup` opens what `-destination auth` opens, and the page reads the name itself. In the symbol's place a line may name a view the app has, drawn once as the tab's image in its own colours (`seer: Seer \"Seer\" SeerMark().frame(width: 30, height: 30) default`); `"tabBar": "icons"` drops the tabs' titles, `"tint": "Color.accent"` colours the selected tab, `"tabFeedback": "light"` gives a light impact on a tab change, and `"overlays": ["Onboarding"]` draws a page over the tabs, under every sheet.

        modals: {"make": "modals"} writes ModalService and its host: `modals.sheet(id: "compose", detents: [.medium, .large]) { … }`, `modals.alert(…)`, `modals.toast("Saved", style: .success)`, `modals.travel(id: "draft", title: "Draft") { … }` (a panel that stays while you browse), and on the Mac `modals.window(id:title:size:) { … }`. `"toasts": "window"` shows the toasts on iOS in a window of their own above alerts, over every sheet, each a card with a subtitle when given (`modals.toast("Category created!", subtitle: "And assigned to your note", style: .success)`), its text in `"toastDesign": "serif"` when the app's type is serif.

        package: {"make": "package", "name": "RecipeKit"} writes a kit in Packages/RecipeKit and links it into the app; `make: service` with `"into": "Packages/RecipeKit"` puts a public service in it.

        link: {"make": "link"} in a project this agent did not make links Granite into every app target and adds the root, the boot and settings services and the root page around the app's ContentView.

        Not for an API's client (network), the app's value types (models), its look (design, loom), or menus and entitlements (platform).
        """#

    public static func output(from events: [GraniteFrame]) -> GraniteResult? { events.compactMap(\.result).last }

    public init() {}

    public func run(_ input: Input, context: Context) -> AsyncThrowingStream<GraniteFrame, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var input = input
                    if input.directory == nil { input.directory = context.host.directory }
                    let result = try await Self.write(input, model: context.host.model, note: context.host.note) { continuation.yield($0) }
                    continuation.yield(.written(result))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole call: the lines read, the files made (the host's model asked where a line says to), staged, checked
    /// and written together.
    static func write(_ input: Input, model: (any AgentHostModel)?, note: @escaping @Sendable (String) -> Void,
                      yield: @escaping @Sendable (GraniteFrame) -> Void) async throws -> GraniteResult {
        let workspace = Workspace(directory: input.directory)
        var plan: Plan
        switch input.make {
        case .project: plan = try ProjectMake(input: input, files: workspace.files).plan()
        case .package: plan = try PackageMake(input: input, workspace: workspace).plan()
        case .link: plan = try LinkMake(input: input, workspace: workspace).plan()
        case .service: plan = try await ServiceMake(input: input, workspace: workspace, model: model, note: note, yield: yield).plan()
        case .component: plan = try await ComponentMake(input: input, workspace: workspace, model: model, note: note, yield: yield).plan()
        case .navigation: plan = try NavigationMake(input: input, workspace: workspace).plan()
        case .modals: plan = try ModalsMake(input: input, workspace: workspace).plan()
        }
        if input.make != .project { try ProjectSync.include(&plan, in: workspace) }
        PackageImports.add(to: &plan, index: ProjectIndex(root: workspace.root))
        let expected = GraniteMeasure.expected(input)
        guard !plan.files.isEmpty else {
            return GraniteResult(path: nil, paths: [], make: input.make.rawValue, types: plan.types, notes: plan.notes, expected: expected)
        }
        note("writing \(plan.files.count) file\(plan.files.count == 1 ? "" : "s") for \(input.make.rawValue)")
        let existed = Set(plan.files.map(\.url.path).filter { FileManager.default.fileExists(atPath: $0) })
        let written = try workspace.files.write(plan.files.map { ($0.url, $0.text) })
        return GraniteResult(path: written.first, paths: written, make: input.make.rawValue, types: plan.types, notes: plan.notes,
                             made: GraniteMeasure.made(expected, make: input.make, written: written, existed: existed), expected: expected)
    }
}
