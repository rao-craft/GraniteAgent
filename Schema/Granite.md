# craft-agent/1 · granite

Makes and grows an iOS + macOS app on Granite — the Xcode project, Granite linked into an existing one, kits, services with their reducers and tests, pages laid out from what they show, navigation and modals.

granite's copy of Craft's agent standard (`craft-agent/1`, Craft's `Schema/Agent.md`), written by
`craft agents schema granite` from its record. Everything above **Changes** is written again each time; Changes is
granite's own log.

| File | What it holds |
| --- | --- |
| [`granite.input.schema.json`](granite.input.schema.json) | What it takes, as JSON Schema |
| [`granite.answer.schema.json`](granite.answer.schema.json) | What it answers: `granite-answer/1` with its own kinds |
| [`examples/granite.answer.json`](examples/granite.answer.json) | A real answer, from a regime run |

## What it takes

| Field | Required | What it is |
| --- | --- | --- |
| `make` | yes | what to make: project (a new iOS + macOS app), package (a kit of services), link (Granite into an Xcode project this agent did not make), service, component (a page), navigation, modals |
| `name` | no | the app's or the kit's name, letters and digits, like `Recipes`: project and package |
| `bundleId` | no | the app's bundle identifier; com.example.<name> when left out: project |
| `team` | no | the 10-character Apple team id the app signs with: project |
| `platforms` | no | the lowest OS each app runs on, one a line: `iOS 26`, `macOS 26`; iOS 17 and macOS 14 when left out: project |
| `type` | no | the service (`Feed` makes FeedService) or the page (`Feed`) to make |
| `into` | no | the folder, relative to the project; Services/<Type> or Components/<Type> when left out; a kit's folder (`Packages/RecipeKit`) puts a public service in the kit |
| `state` | no | fields, one a line, in the models syntax: `posts [Post] = []`, `selected String?`; a page's `let post Post` is an input it is made with |
| `events` | no | a service's work, one a line: `load(page Int) -> posts = API.posts(page: page) "loads a page"`; `+> posts` appends; with no `= call` the host's model writes the work |
| `relays` | no | the services a service's work calls, a page reads, or navigation's `gate` reads: `feed: FeedService` or `Feed` |
| `layout` | no | how a page draws: list, grid, detail, form, settings, search, compose, tabs, threePane, blank |
| `shows` | no | what a page draws: `items = feed.state.posts`, `item = …`, `selection = feed.state.selected`, `title = "Feed"`, `empty = "No posts yet"`; a row of a form `"Section/Label" = config.state.field` |
| `actions` | no | what a page does: `refresh = try await feed.load(page: 1)`, `more = …`, `open(post Post) = …`, `compose "New Post" square.and.pencil = …` |
| `views` | no | a page's subviews: `row(post Post, vote (Bool) -> Void) "title, author and score, with a vote"`; a closure is an action the view sends up with `bubble`, routed by the page to the action of its name; a description is what the host's model writes the body from |
| `body` | no | a blank page's body as Swift, written as given: the view the app has, filled from the page's relays and actions (`FeedView(posts: feed.state.posts, actions: …)`) |
| `destinations` | no | the app's places, one a line: `feed: Feed "Feed" house`, or in the symbol's place a view the app has drawn as the tab's image (`seer: Seer "Seer" SeerMark().frame(width: 30, height: 30)`); after the symbol, `default` opens the app on it (else the first), `sheet` puts it in a sheet over the tabs (`layout.present(.wallet)`), `sheet over models` or `sheet over profile` a sheet a launch naming it puts up over that tab, or stacked on that sheet, `gate` shows it instead of the tabs while `gate` holds; `\| Detail` names the view beside it in the split style. A line `auth.signup -> auth` is a launch alias, any name with dots: `-destination auth.signup` opens what `-destination auth` opens (the gate's alias holds the gate, any other opens past it) and stays readable in the `destination` default |
| `gate` | no | navigation's gate: a Swift condition over a relay's state, the relay named in `relays` (`account.state.session == nil`, `account: AccountService`); while it holds, the destination marked `gate` is shown full screen instead of the tabs, and a launch with `-destination <another>` opens past it |
| `style` | no | how the app moves between destinations: adaptive (tabs on iPhone, a sidebar on iPad and Mac), tabs, sidebar, split |
| `tabBar` | no | what a tab bar item shows: labels (its image over its title; when left out) or icons (its image alone, an empty title, as `Tab("", …)`) |
| `tint` | no | the colour of the tab bar's selected item, a Swift colour: `Color.accent`; the app's accent colour when left out |
| `tabFeedback` | no | the impact felt when the tab changes on iPhone: light, medium, heavy, soft, rigid; none when left out |
| `overlays` | no | views navigation draws over the tabs, bottom to top, under every sheet: a page the app has, `Onboarding` (a first-run layer that takes touches only where it draws) |
| `toasts` | no | where modals shows its toasts: overlay (over the root view; when left out) or window (on iOS in a window of their own one level above alerts, `.alert + 1`, over every sheet and alert, a touch elsewhere passing through, the styles in circle symbols; the Mac keeps the overlay) |
| `toastDesign` | no | the font design of the toasts' text in their own window, with `toasts: window`: serif, rounded or monospaced; the system's when left out |
| `root` | no | the root page; Home when left out |
| `packages` | no | remote packages the app links, pinned: `https://github.com/kean/Nuke@<40-hex revision> Nuke NukeUI` |
| `imports` | no | modules the files import beside Foundation, SwiftUI and Granite; a local package's are found on their own |
| `persist` | no | whether a service's state is kept between launches |
| `notes` | no | what the work or the page is for, in a sentence: what the host's model writes bodies from |
| `rounds` | no | how many answers the host's model may give one body before the call is refused; 3 when left out |

`directory` is filled by Craft with the project folder. The person's request and the host's model are offered
beside the call, never in it.

## What it makes

| Kind | What | Into | Never |
| --- | --- | --- | --- |
| `project` | an iOS and macOS app on Granite: its Xcode project, the root that boots it, its environment and settings services and its Home page | `*.xcodeproj`, `Shared/App.swift`, `Shared/AppDelegate.swift`, `Shared/Assets.xcassets/*`, `Shared/Utility/AppRoot.swift`, `Services/EnvironmentService/*`, `Services/ConfigService/*`, `Components/Home/*`, `Tests/*`, `UITests/*` | an API's client or the app's value types |
| `kit` | a Swift package of the app's own, linked into it, for public services | `Packages/*` |  |
| `service` | a service: its state, its one writer, the work its reducers run, and its tests | `Services/*`, `Packages/*/Sources/*/Services/*`, `Tests/*OpsTests.swift` |  |
| `page` | a page that composes the app's views and reads its services; a view the app already has (a kit's FeedView) is shown by a blank page, never rewritten | `Components/*` | the views a page shows |
| `navigation` | the app's destinations and how it moves between them: tabs on iPhone, a sidebar on iPad and the Mac | `Shared/Utility/AppDestination.swift`, `Shared/Utility/Routes.swift`, `Shared/Utility/Device.swift`, `Services/LayoutService/*`, `iOS/PlatformNavigationView.swift`, `macOS/PlatformNavigationView.swift` |  |
| `modals` | the app's sheets, alerts, toasts and travelling panels, from one service | `Services/ModalService/*` |  |

## What it answers

A `granite-answer/1` answer (Granite's `Schema/GraniteAgent.md` §4.2): `paths`, `made` against `expected` by kind and
name, `problems` for what it could only do in part, `payloads` for files that keep a standard of their own, and its
own keys beside them. Craft measures each call by what it made of what it expected.

## How it refuses

With an `AgentRefusal`: a kind and reasons, each with its fix. `input` and `call` are the call's to correct; `build`,
`device`, `reach`, `model` and `host` what stood in the way; `answer` and `parse` its own bug.

## Changes

Each change made to make this agent more precise, dated, with the regime run that measured it and what it
made of what it was asked before and after (`TESTING.md`). Newest first.

### 2026-11-15 · navigation: launch aliases, sheets over a tab or a sheet, the shell as the original draws it; modals: a toast window above alerts

Seer is checked by launching it straight into each of its screens with `-destination <name>`, and many of those
names are not places of their own: Sign Up and the one-time code are steps of Sign In, a restored reply is the Seer
tab, Feedback is pushed in Settings. Some of its sheets go up over a tab that is not the default (Profile over
Models) or over another sheet (Settings over Profile, Sinatra Threads over Echoes), and its toast shows over every
sheet and alert. Navigation knew one name per place, put every sheet up over the default tab, and modals drew the
toasts in the root view's overlay, under sheets.

A destinations line `auth.signup -> auth` is now a launch alias, any name with dots: `-destination auth.signup`
opens exactly what `-destination auth` opens (the tab selected, the sheet up, the gate shown or passed; the gate's
alias holds the gate, any other opens past it), and the name stays in the `destination` default for the page to open
its own inner state. `AppDestination.launchNames` lists every name a launch may give and `AppDestination(launchName:)`
reads one; `LayoutOpsTests` open each alias. A sheet line may end `sheet over models` or `sheet over profile`: a
launch naming it selects that tab first, or puts that sheet up first and this one on it, unanimated, as if the person
had gone there; with an `over` in the call, a sheet a page presents goes up over whatever is up, and its close takes
down only it. An alias naming nothing, a cycle, a name used twice, and `over` on a tab, over the gate, over itself or
round a cycle are refused with every reason. `make: modals` takes `toasts: window`: on iOS the toasts show in a
passthrough `UIWindow` at `.alert + 1` over the scene, each a card as wide as the screen as the original draws its
toast (the style's symbol at 22 semibold beside the message, the ultra-thin material rounded at 24, a shadow, a
spring of 0.4 s, 3 s on screen), the success, error, warning and info styles in green `checkmark.circle.fill`, red
`xmark.circle.fill`, orange `exclamationmark.triangle.fill` and blue `info.circle.fill`; the Mac keeps the overlay.
In the window a toast takes a subtitle under its message, as the original's do (`modals.toast("Category created!",
subtitle: "And assigned to your note", style: .success)`), the message in the headline and the subtitle in the
caption, secondary, both in `toastDesign` (`serif` for Seer, the system's design when left out); `toastDesign`
without `toasts: window` is refused.

The shell is also held to the original's look (Components/Main/MainView.swift): its tabs show their images alone,
the middle one is the app's medallion in full colour, the selected tab takes the brand's tint, a tab change gives a
light impact, and the first-run layer lies over the tabs. In the symbol's place a destinations line may name a view
the app has (`seer: Seer "Seer" SeerMark().frame(width: 30, height: 30) default`): `AppDestination.image(scale:)`
draws it once with `ImageRenderer` at the screen's scale, `.renderingMode(.original)`, so the tab bar never tints it.
`tabBar: icons` gives each tab item an empty title, as `Tab("", …)` writes it; `tint: Color.accent` puts `.tint` on
the tab view; `tabFeedback: light` writes `.sensoryFeedback(.impact(weight: .light), trigger:
layout.state.destination)` on iOS; `overlays: ["Onboarding"]` draws each page named over the tabs, bottom to top,
under every sheet. A drawn view or an overlay the project lacks is refused naming the page to make first. A call with
none of the new words writes what it wrote before, byte for byte (`SameBytesTests` holds twelve navigation and modals
calls to the bytes of 4e59a5e).

Measured: not yet. The Seer measure (Craft) is the first.

### 2026-11-15 · navigation: a default tab, sheets over the tabs, a gate before them

Seer's shell is Sign In until there is a session, then three tabs with the middle one first, and its other places
sheets over the tabs, each reachable from `-destination <name>`. Navigation made every destination a tab, always
opened on the first and had no gate. A destination line may now end in `default` (a plain launch opens on it, every
time), `sheet` (an `AppDestination` case presented at the large detent with a close button, `layout.present(.wallet)`,
and `-destination wallet` opens the default tab with it up) or `gate` (shown full screen instead of the tabs while
the new `gate` input, a condition over a relay's state, holds; a launch naming any other destination opens past it,
for checking screens). Two defaults, two gates, no tab left, a gate line or condition without the other, and a relay
or state field the project lacks are refused with every reason. A call with none of the words writes what it wrote
before, byte for byte.

Measured: not yet. The Seer measure (Craft) is the first.

### 2026-11-05 · a subview's actions bubble up to its page

Granite replaced `GraniteAction` with `bubble`/`onBubble` (Granite 7ff3352), and Loom moved to it. A page's subview no
longer stores optional closures that the page fills: each closure of a `views` line is a `GraniteBubble.Name` of the
view's own (`.recipeDetailHeaderRate`, prefixed by the view so no two collide), sent by a function of the view that
holds the exact type a route matches (`rate(_ value: Int)`), and the page routes it with `onBubble` where it draws the
view, to the action of its name. Its controls are always drawn; a closure no action routes is said in the notes. The
host's model is told the functions a subview has, and a blank page what each subview sends and how to route it.
The apps and kits it makes are pinned to Granite 7ff3352, the first with `bubble`.

Measured: not yet. The views lines read as before; the next regime chain is the first measure.

### 2026-11-04 · answer `granite-answer/1`; a blank page's given body held to the names rule

granite says what it makes (project, kit, service, page, navigation, modals) and where each lands, and answers `made` against `expected` read off the call's own lines. A body the host's model never got right is refused as kind `model`, no longer the call's to fix. A blank page's body given in the call is now checked as an asked one is: in the Margin regime (2026-11-04, turn 4) a given body named `posts` and `phase`, which the page never defined, and the pages did not build. (4210ca9)

Measured: not yet. Answers before this were pre-standard, so there is no precision to compare; the next regime chain on Margin is the first measure.

### 2026-11-04 · refuse a state field a service does not have; write Testing's names with their module

In the Margin regime (2026-11-03/04) granite took `state.nextCursor` for a state with no such field, and its Ops tests wrote a bare `Comment` beside `import Testing`, which declares one. Both failed the build, and the model then rewrote the services by hand. (70589c8)

Measured: not yet. Answers before this were pre-standard, so there is no precision to compare; the next regime chain on Margin is the first measure.
