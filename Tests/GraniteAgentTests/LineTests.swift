import XCTest
@testable import GraniteAgent

/// The lines a model writes, read: every form the guide promises, and a reason for every line refused.
final class LineTests: XCTestCase {
    func testEventLines() throws {
        let load = try EventLine.parse(#"load(page Int = 1) -> posts = try await LemmyAPI.posts(page: page) "loads one page""#)
        XCTAssertEqual(load.verb, "load")
        XCTAssertEqual(load.params.map(\.name), ["page"])
        XCTAssertEqual(load.params[0].defaultValue, "1")
        XCTAssertEqual(load.write, .replace("posts"))
        XCTAssertEqual(load.expression, "LemmyAPI.posts(page: page)", "the agent adds try await itself")
        XCTAssertEqual(load.doc, "loads one page")
        XCTAssertEqual(load.typeName, "Load")
        let more = try EventLine.parse("more(page: Int) +> posts = API.page(page, filter: \"a, b\")")
        XCTAssertEqual(more.write, .append("posts"))
        XCTAssertEqual(more.expression, "API.page(page, filter: \"a, b\")")
        let vote = try EventLine.parse("vote(post Post, up Bool) = API.vote(post.id, up: up)")
        XCTAssertEqual(vote.write, .none)
        XCTAssertEqual(vote.params.map(\.type.description), ["Post", "Bool"])
        let refresh = try EventLine.parse(#"refresh -> posts "the first page, newest first""#)
        XCTAssertNil(refresh.expression, "with no call, the host's model writes the work")
        XCTAssertEqual(refresh.params, [])
    }

    func testEventLinesThatAreRefusedSayWhy() {
        let refused: [(String, String)] = [
            ("Load(page Int)", "lowerCamelCase"),
            ("set(value Int)", "the service's own"),
            ("load(ticket UUID)", "uses that name itself"),
            ("load(page Int, page Int)", "named twice"),
            ("load(page Int) -> ", "names the state field"),
            ("load(page Int) => posts", "not `=> posts`"),
            ("load(page Int -> posts", "never closed"),
        ]
        for (line, reason) in refused {
            XCTAssertThrowsError(try EventLine.parse(line), line) { error in
                XCTAssertTrue("\(error)".contains(reason), "\(line) → \(error)")
            }
        }
    }

    func testRelayLines() throws {
        XCTAssertEqual(try RelayLine.parse("feed: FeedService"), Relay(name: "feed", type: "FeedService"))
        XCTAssertEqual(try RelayLine.parse("Feed"), Relay(name: "feed", type: "FeedService"))
        XCTAssertEqual(try RelayLine.parse("posts Feed"), Relay(name: "posts", type: "FeedService"))
        XCTAssertEqual(try RelayLine.parse("URLCache"), Relay(name: "urlCache", type: "URLCacheService"))
        XCTAssertThrowsError(try RelayLine.parse("feed: feedService"))
    }

    func testShowLines() throws {
        let items = try ShowLine.parse("items = feed.state.posts")
        XCTAssertEqual(items.role, "items")
        XCTAssertEqual(items.expression, "feed.state.posts")
        let title = try ShowLine.parse(#"title = "Feed""#)
        XCTAssertTrue(title.isLiteral)
        XCTAssertEqual(title.literal, "Feed")
        let row = try ShowLine.parse(#""Appearance/Theme" = config.state.appearance"#)
        XCTAssertEqual(row.key, .label(section: "Appearance", text: "Theme"))
        let plain = try ShowLine.parse(#""Show tips" = config.state.showsTips == true"#)
        XCTAssertEqual(plain.key, .label(section: nil, text: "Show tips"))
        XCTAssertEqual(plain.expression, "config.state.showsTips == true", "only the first `=` splits")
        XCTAssertThrowsError(try ShowLine.parse("items feed.state.posts"))
        XCTAssertThrowsError(try ShowLine.parse("Items = x")) { XCTAssertTrue("\($0)".contains("not a role")) }
    }

    func testActionLines() throws {
        let refresh = try ActionLine.parse("refresh = try await feed.load(page: 1)")
        XCTAssertEqual(refresh.name, "refresh")
        XCTAssertEqual(refresh.label, "Refresh")
        let compose = try ActionLine.parse(#"compose "New Post" square.and.pencil = modals.sheet { Write() }; feed.set(.clear)"#)
        XCTAssertEqual(compose.title, "New Post")
        XCTAssertEqual(compose.symbol, "square.and.pencil")
        XCTAssertEqual(compose.statements, ["modals.sheet { Write() }", "feed.set(.clear)"])
        let delete = try ActionLine.parse("deletePost(post Post, reason String = \"spam\") = try await feed.delete(post)")
        XCTAssertEqual(delete.params.map(\.name), ["post", "reason"])
        XCTAssertTrue(delete.isDestructive)
        XCTAssertEqual(delete.label, "Delete Post")
        XCTAssertThrowsError(try ActionLine.parse("refresh feed.load()"))
        XCTAssertThrowsError(try ActionLine.parse(#"share "Share" Square = x"#)) { XCTAssertTrue("\($0)".contains("SF Symbol")) }
    }

    func testViewLines() throws {
        let row = try ViewLine.parse(#"row(post Post, vote (Bool) -> Void, onShare: () -> Void) "title, author and score""#)
        XCTAssertEqual(row.role, "row")
        XCTAssertEqual(row.roleName, "Row")
        XCTAssertEqual(row.values.map(\.name), ["post"])
        XCTAssertEqual(row.closures.map(\.name), ["vote", "onShare"])
        XCTAssertEqual(row.description, "title, author and score")
        XCTAssertEqual(ComponentSpec.closureInputs("(Bool) -> Void"), ["Bool"])
        XCTAssertEqual(ComponentSpec.closureInputs("() -> Void"), [])
        XCTAssertNil(try ViewLine.parse("header(count Int)").description)
        XCTAssertThrowsError(try ViewLine.parse("row(post)")) { XCTAssertTrue("\($0)".contains("needs a name and a type")) }
    }

    func testDestinationLines() throws {
        let feed = try DestinationLine.parse(#"feed: Feed "Feed" house"#)
        XCTAssertEqual(feed, Destination(name: "feed", view: "Feed()", viewType: "Feed", title: "Feed", symbol: "house", detail: nil, detailType: nil))
        let inbox = try DestinationLine.parse(#"inbox: Inbox(filter: .unread) "Inbox" tray.full | Message"#)
        XCTAssertEqual(inbox.view, "Inbox(filter: .unread)")
        XCTAssertEqual(inbox.detail, "Message()")
        XCTAssertEqual(inbox.symbol, "tray.full")
        for (line, reason) in [("feed Feed \"Feed\" house", "is `name: View"), (#"feed: Feed Feed house"#, "in quotes"), (#"feed: Feed "Feed""#, "SF Symbol")] {
            XCTAssertThrowsError(try DestinationLine.parse(line), line) { XCTAssertTrue("\($0)".contains(reason), "\(line) → \($0)") }
        }
    }

    /// After the symbol: `default` (the tab a plain launch opens on), `sheet` (over the tabs), `gate` (before them).
    func testDestinationLinesSayWhereTheySit() throws {
        let seer = try DestinationLine.parse(#"seer: Seer "Seer" sparkles default"#)
        XCTAssertEqual(seer, Destination(name: "seer", view: "Seer()", viewType: "Seer", title: "Seer", symbol: "sparkles", detail: nil, detailType: nil,
                                         place: .tab, isDefault: true))
        XCTAssertEqual(try DestinationLine.parse(#"wallet: Wallet "Wallet" creditcard sheet"#).place, .sheet)
        let auth = try DestinationLine.parse(#"auth: SignIn "Sign In" person gate"#)
        XCTAssertEqual(auth.place, .gate)
        XCTAssertEqual(auth.title, "Sign In")
        XCTAssertFalse(auth.isDefault)
        let inbox = try DestinationLine.parse(#"inbox: Inbox "Inbox" tray default | Message"#)
        XCTAssertTrue(inbox.isDefault)
        XCTAssertEqual(inbox.detail, "Message()")
        XCTAssertEqual(try DestinationLine.parse(#"feed: Feed "Feed" house"#).place, .tab, "a line with no word is a tab, as before")
        XCTAssertNil(try DestinationLine.parse(#"wallet: Wallet "Wallet" creditcard sheet"#).over)
        let settings = try DestinationLine.parse(#"settings: Settings "Settings" gearshape sheet over profile"#)
        XCTAssertEqual(settings.place, .sheet)
        XCTAssertEqual(settings.over, "profile")
        XCTAssertEqual(try DestinationLine.parse(#"contributions: Contributions "Contributions" person.2 over void.reply sheet"#).over, "void.reply",
                       "`over` may come before `sheet`, and name an alias")
        for (line, reason) in [(#"feed: Feed "Feed" house later"#, "comes `default`, `sheet` or `gate`, not `later`"),
                               (#"feed: Feed "Feed" house sheet gate"#, "not both"),
                               (#"feed: Feed "Feed" house sheet default"#, "a sheet is not a tab"),
                               (#"feed: Feed "Feed" house gate default"#, "a gate is not a tab"),
                               (#"feed: Feed "Feed" house default default"#, "`default` is said twice"),
                               (#"feed: Feed "Feed" house over models"#, "a tab is not a sheet: say `sheet over models`"),
                               (#"auth: SignIn "Sign In" person gate over seer"#, "a gate is not a sheet"),
                               (#"feed: Feed "Feed" house sheet over"#, "`over` names what the sheet goes up over"),
                               (#"feed: Feed "Feed" house sheet over sheet"#, "`over` names what the sheet goes up over"),
                               (#"feed: Feed "Feed" house sheet over a over b"#, "`over` is said twice"),
                               (#"feed: Feed "Feed" house sheet over a/b"#, "`a/b` is not a destination's name")] {
            XCTAssertThrowsError(try DestinationLine.parse(line), line) { XCTAssertTrue("\($0)".contains(reason), "\(line) → \($0)") }
        }
    }

    /// In the symbol's place a line may name a view the app has, drawn as the tab's image: a view made by a call, with
    /// modifiers after it, or an image in the assets; anything else there is refused saying what goes there.
    func testADestinationMayDrawAViewAsItsImage() throws {
        let seer = try DestinationLine.parse(#"seer: Seer "Seer" SeerMark().frame(width: 30, height: 30) default"#)
        XCTAssertEqual(seer.drawn, "SeerMark().frame(width: 30, height: 30)")
        XCTAssertEqual(seer.drawnType, "SeerMark")
        XCTAssertEqual(seer.symbol, "")
        XCTAssertTrue(seer.isDefault)
        let asset = try DestinationLine.parse(#"seer: Seer "Seer" Image("LogoMark") default"#)
        XCTAssertEqual(asset.drawn, #"Image("LogoMark")"#)
        XCTAssertEqual(asset.drawnType, "Image")
        let sheet = try DestinationLine.parse(#"wallet: Wallet "Wallet" WalletGlyph(size: 30) sheet over models"#)
        XCTAssertEqual(sheet.drawn, "WalletGlyph(size: 30)")
        XCTAssertEqual(sheet.place, .sheet)
        XCTAssertEqual(sheet.over, "models")
        XCTAssertNil(try DestinationLine.parse(#"feed: Feed "Feed" house"#).drawn)
        for line in [#"seer: Seer "Seer" SeerMark default"#, #"seer: Seer "Seer" SeerMark().frame(width: 30 default"#,
                     #"seer: Seer "Seer" SeerMark().frame default"#, #"seer: Seer "Seer" SeerMark()frame() default"#] {
            XCTAssertThrowsError(try DestinationLine.parse(line), line) { error in
                XCTAssertTrue("\(error)".contains("is not a view drawn as the tab's image"), "\(line): \(error)")
            }
        }
    }

    /// A launch alias: another name a launch may give for a destination, dots allowed (`auth.signup -> auth`); a
    /// destination line, even one whose view's arguments hold an arrow, is not one.
    func testLaunchAliasLines() throws {
        XCTAssertEqual(try DestinationLine.alias("auth.signup -> auth"), LaunchAlias(name: "auth.signup", target: "auth"))
        XCTAssertEqual(try DestinationLine.alias("  settings.feedback->settings "), LaunchAlias(name: "settings.feedback", target: "settings"))
        XCTAssertEqual(try DestinationLine.alias("model-edit -> model.page"), LaunchAlias(name: "model-edit", target: "model.page"))
        XCTAssertNil(try DestinationLine.alias(#"feed: Feed "Feed" house"#))
        XCTAssertNil(try DestinationLine.alias(#"feed: Feed(sort: { (a: Int) -> Bool in a > 0 }) "Feed" house"#))
        for (line, reason) in [("-> auth", "a launch alias is `name -> destination`"), ("auth signup -> auth", "`auth signup` is not a name a launch gives"),
                               ("auth.signup ->", "a launch alias is `name -> destination`"), ("auth.signup -> auth gate", "`auth gate` is not a destination's name"),
                               (".signup -> auth", "is not a name a launch gives")] {
            XCTAssertThrowsError(try DestinationLine.alias(line), line) { XCTAssertTrue("\($0)".contains(reason), "\(line) → \($0)") }
        }
    }

    func testPackageLines() throws {
        let revision = String(repeating: "a1", count: 20)
        let nuke = try PackageLine.parse("https://github.com/kean/Nuke@\(revision) Nuke NukeUI")
        XCTAssertEqual(nuke.requirement, .revision(revision))
        XCTAssertEqual(nuke.products, ["Nuke", "NukeUI"])
        XCTAssertEqual(nuke.identity, "Nuke")
        XCTAssertEqual(try PackageLine.parse("https://github.com/apple/swift-collections.git@1.1.4 Collections").identity, "swift-collections")
        XCTAssertThrowsError(try PackageLine.parse("https://github.com/kean/Nuke@main Nuke")) { XCTAssertTrue("\($0)".contains("never a branch")) }
        XCTAssertThrowsError(try PackageLine.parse("https://github.com/kean/Nuke@\(revision)")) { XCTAssertTrue("\($0)".contains("name the products")) }
    }

    func testFieldLinesAreTheModelsSyntax() throws {
        let field = try FieldLine.parseField(#"posts [Post] = [] "what the feed shows""#, in: "")
        XCTAssertEqual(field.type, .array(.named("Post")))
        XCTAssertEqual(field.defaultValue, "[]")
        XCTAssertEqual(field.doc, "what the feed shows")
        XCTAssertEqual(try FieldLine.parseField("selected: string?", in: "").type, .optional(.named("String")))
        XCTAssertThrowsError(try FieldLine.parseField("Selected String", in: ""))
    }

    func testNamesAreSaidAsSwiftSaysThem() {
        XCTAssertEqual(SwiftName.service("Config").type, "ConfigService")
        XCTAssertEqual(SwiftName.service("ConfigService").base, "Config")
        XCTAssertEqual(SwiftName.relayName("FeedService"), "feed")
        XCTAssertEqual(SwiftName.title("markAllRead"), "Mark All Read")
        XCTAssertEqual(SwiftName.member("default"), "`default`")
        XCTAssertEqual(SwiftName.member("open"), "open", "a contextual keyword is a name like any other")
    }

    /// `_ name Type` is taken as `name Type` (Margin, 2026-11-01).
    func testAnEventParameterMayStartWithAnUnderscore() throws {
        let event = try EventLine.parse("create(_ body NewPost) -> post = API.create(body)")
        XCTAssertEqual(event.params.map(\.name), ["body"])
    }
}
