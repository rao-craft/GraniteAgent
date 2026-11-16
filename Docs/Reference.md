# GraniteAgent reference

How the `granite` agent is found, what a call takes and answers, the lines it reads, what each make writes, and how
to build and test it. What it is for is in the [README](../README.md); the agent standard it follows is in
[Schema/Granite.md](../Schema/Granite.md).

## How an app finds it

GraniteAgent is a `GraniteAgentPackage` (the type is `GraniteAppAgent`, since `GraniteAgents` already has a
`GraniteAgent`), and it carries a record in its binary:

```swift
@used @section("__DATA_CONST,__granite")
let graniteRecord: GraniteRoster.Record = { GraniteRoster.record(GraniteAppAgent.self) }
```

In [Craft](https://github.com/riteshpakala/Craft), install it from the Agent Store or with
`craft agents add https://github.com/rao-craft/GraniteAgent.git`, then say `$granite` in a request:

```
$granite start a recipe app, then a service that keeps the recipes (loaded a page at a time, kept between
launches) and a list page of them with pull to refresh and a favourite in each row's menu
```

The model writes one call per step; each shows on Craft's agent map as `granite-1`, `granite-2`…, and the files they
name are built and tested with the turn. Calls run one at a time (`lanes` 1): several makes edit the project file and
the root that holds the relays.

## What a call takes and answers

| Field | | |
|---|---|---|
| `make` | required | `project`, `package`, `link`, `service`, `component`, `navigation` or `modals` |
| `name` | project, package | the app's or the kit's name: `Recipes` |
| `bundleId`, `team` | project | `com.example.<name>` when left out; the 10-character team id |
| `platforms` | project | the lowest OS each app runs on, one a line: `iOS 26`, `macOS 26`; iOS 17 and macOS 14 when left out |
| `type` | service, component | `Feed` makes `FeedService` (a service) or `Feed` (a page) |
| `into` | optional | the folder, relative to the project; `Services/<Type>` and `Components/<Type>` when left out; a kit's folder puts a public service in the kit |
| `state` | service, component | fields in the models syntax, one a line: `posts [Post] = []`, `selected String?`; a page's `let post Post` is an input |
| `events` | service | the work, one a line (below) |
| `relays` | service, component, navigation | `feed: FeedService`, or `Feed`; navigation reads them only for its `gate` |
| `layout` | component | `list`, `grid`, `detail`, `form`, `settings`, `search`, `compose`, `tabs`, `threePane`, `blank` |
| `shows`, `actions`, `views` | component | what the page draws, does, and its subviews (below) |
| `destinations`, `style` | navigation | `feed: Feed "Feed" house`, then `default`, `sheet` (`sheet over models`, `sheet detents medium large`) or `gate` when it is more than a tab, and `auth.signup -> auth` for another name a launch may give (below); `adaptive`, `tabs`, `sidebar` or `split` |
| `gate` | navigation | the condition over a relay's state that holds the gate: `account.state.session == nil`, its relay in `relays` |
| `tabBar`, `tint` | navigation | `labels` when left out, `icons` for each tab's image alone (an empty title, as `Tab("", …)`); the selected tab's colour, a Swift colour (`Color.accent`), the accent colour when left out |
| `tabFeedback` | navigation | the impact a tab change gives on iPhone: `light`, `medium`, `heavy`, `soft` or `rigid`; none when left out |
| `overlays` | navigation | pages drawn over the tabs, bottom to top, under every sheet: `Onboarding` |
| `toasts` | modals | `overlay` when left out; `window` shows the toasts on iOS in a window of their own at `.alert + 1`, over every sheet and alert |
| `toastDesign` | modals | with `toasts: window`, the font design of the toasts' text: `serif`, `rounded` or `monospaced`; the system's when left out |
| `root` | project, link, navigation | the root page; `Home` when left out |
| `packages` | project, package, link | pinned remote packages: `https://github.com/kean/Nuke@<revision> Nuke NukeUI` |
| `imports` | service, component | modules to import; a local package's are found on their own |
| `persist` | service | whether the state is kept between launches |
| `notes` | service, component | what the work or the page is for: what the host's model writes bodies from |
| `rounds` | optional | how many answers the model may give one body; 3 when left out |
| `directory` | the host's | the folder the host works in; a host fills it and does not show it to a model |

The answer is a `GraniteResult`: every file written or edited (`path`, `paths`, absolute, the project file and the
root included), the types written, and a sentence for each decision.

## The lines

```
load(page Int) -> posts = LemmyAPI.posts(page: page) "loads one page"     an event: -> replaces a field
more(page Int) +> posts = LemmyAPI.posts(page: page)                       +> appends a page to a list
refresh() -> posts "the first page, newest first"                          no `= call`: the model writes it

items = feed.state.posts                  shows: a role (items, item, selection, query, sidebar, title, empty)
"Appearance/Theme" = config.state.appearance        or a row of a form, its control chosen by the field's type
refresh = try await feed.load(page: 1)    actions: refresh, more, open, submit and search do what they say
favor(post Post) "Favorite" star = …       an action on an item is in its row's menu and swipe; others are toolbar buttons
row(post Post, vote (Bool) -> Void) "title, author and score, with a vote"     views: a closure is an action the view bubbles up, routed to the action of its name
feed: Feed "Feed" house | PostDetail       destinations: the detail after a bar shows beside it in the split style
seer: Seer "Seer" sparkles default         default: a plain launch opens on it, not the first, every time
wallet: Wallet "Wallet" creditcard sheet   sheet: over the tabs, not one of them; a page opens it with layout.present(.wallet)
auth: SignIn "Sign In" person gate         gate: shown instead of the tabs while `gate` holds (one, with `gate`)
profile: Profile "Profile" person sheet over models      over: a launch naming it selects that tab first
settings: Settings "Settings" gearshape sheet over profile    or puts that sheet up first and this one on it
world: World "The World" infinity sheet over seer detents medium large    detents: the heights it rests at, up at the first
model: Model "Model" folder sheet over models detents fraction(0.6)        medium, large, fraction(0.6), height(320)
auth.signup -> auth                        a launch alias: opens what `auth` opens; any name, dots allowed
seer: Seer "Seer" SeerMark().frame(width: 30, height: 30) default    in the symbol's place, a view the app has, drawn as the tab's image
```

Every destination opens from a launch with `-destination <name>`: a tab on it, a sheet up over the default tab, or
over what its `over` names, the sheets under it put up first, unanimated. With a gate, a launch with no
`-destination`, or with the gate's own name, holds by the condition; one naming any other destination opens past it,
so a screen is checked with no sign-in and no tap. An alias opens exactly what its destination opens (an alias of the
gate holds the gate) and its name stays in the `destination` default, so the page reads
`UserDefaults.standard.string(forKey: "destination")` to open its own inner state. With an `over` in the call, a sheet
a page presents goes up over whatever is up and its close takes down only it. An alias naming nothing, a cycle, a
name used twice, and `over` on a tab, over the gate or round a cycle are refused. A sheet whose line names `detents`
rests at those heights and goes up at the first, a launch's too, with its drag indicator showing; stacked on a sheet,
it keeps its own. One that names none goes up large, as before; `detents` on a tab or the gate, a height that is none
and one named twice are refused.

A view in the symbol's place is drawn once, at the screen's scale, with `ImageRenderer`, and shown in its own colours
(`.renderingMode(.original)`), so a medallion or a logo stays as drawn while the tab bar tints the other tabs; it must
be a view the project has (or `Image("name")` from its assets), and the sidebar shows it the same way. With
`tabBar: icons`, `tint`, `tabFeedback` and `overlays`, the root reads as `TabView(selection:) { … }.tint(Color.accent)
.sensoryFeedback(.impact(weight: .light), trigger: layout.state.destination).overlay { Onboarding() }`; an overlay is a
page the project has, and reads `layout.state.destination` for the tab that is up.

A line it cannot read, a field that does not exist, a relay that would loop, a page the project does not have: the call
is refused with every reason at once, and nothing is written.

## How the output is made

| Make | What it writes |
|---|---|
| project | `<Name>.xcodeproj` from Granite's template (objectVersion 77, synchronized Shared, Components, Services, iOS, macOS, Tests and UITests; an app, unit tests and UI tests per platform, the UI tests skipped in the schemes until turned on, since they need an interactive session to drive the app; Swift 5, iOS 17, macOS 14; Granite pinned at `7ff33526` with GraniteAgents), shared schemes, `@main` App and delegate, `AppCommands`, `AppRoot`, `EnvironmentService` and `ConfigService` with their Ops and tests, the `Home` page that boots the app, `modalHosted()`, the asset catalog |
| service | the struct with its tickets, lane, `set` and `binding` helpers and a ticketed entry per event; its center (`TransientState`, or a persisted `GraniteState` that reads old files); `Set` with a case per field; a reducer per event that marks the start in `reduce` and works in `effect`; `Ops.apply`; Ops tests; a relay in the root |
| component | `<Page>`, `+Center`, `+View` (loading, empty, an error banner with a retry, pull to refresh, load more, a context menu and swipe per item, a toolbar, the first load gated on `isLoaded`), `+Actions`, reducers when asked, and `Views/<Page>.<Role>View.swift` per subview |
| navigation | `AppDestination`, `PlatformNavigationView` for iOS and macOS, `LayoutService`, `Routes` over Granite's router, `Device`, and the root page shown with them; with `sheet`, `AppDestination.tabs` and `isSheet`, a `sheet` in the layout with `present` and `closeSheet`, and the sheet host on both platforms; with `gate`, `AppGate` in the root page's view file, beside the root that shows it; with `over`, `AppDestination.over`, a stack of `sheets` in the layout (`.sheet`, `.sheets`), a launch that puts up each sheet under the one it names, and a stacked sheet host on both platforms; with aliases, `AppDestination.aliases`, `launchNames` and `init?(launchName:)`, which `launchArgument` reads through; with a drawn view, `AppDestination.image(scale:)` over `ImageRenderer`; with `detents`, `AppDestination.detents` and `dragIndicator`, and `LayoutSheetDetents` in both sheet hosts (`.presentationDetents(_:selection:)` from the first); with `tabBar`, `tint`, `tabFeedback` and `overlays`, the tab items, `.tint`, `.sensoryFeedback` (iOS) and `.overlay` on the tab view; `LayoutOpsTests` cover the default, a sheet, the gate's launch rule, each alias, the stacked launch and each sheet's heights |
| modals | `ModalService` (sheets with detents, alerts, toasts, travelling panels, Mac windows; state holds ids, a registry the views), its host views, and the real `modalHosted()`; with `toasts: window`, a passthrough `ModalToastWindow` at `.alert + 1` over the scene on iOS, holding `ModalToastStack`, each toast a card as wide as the screen (its symbol at 22, the message over a subtitle when `modals.toast(_:subtitle:style:)` gives one, in `toastDesign`, the ultra-thin material rounded at 24, a spring of 0.4 s), the overlay kept on the Mac |
| package | `Package.swift`, `<Name>Root`, a test target; inside an app, `Packages/<Name>` linked into every app target |
| link | Granite linked into every app target, Swift 5 on app targets that were on 6, the root, the boot and settings services and a root page written beside the app's code (file references and build files in a project of classic groups), and the root page mounted around the view the App showed |

Everything is made from the lines. The host's model is asked only for what is the app's own: the body of work no
`= call` says how to do, a subview's body its line describes, a blank page. Each answer is checked, parsed with
`swiftc -parse` in its file, and asked again with what was wrong; its examples come from another app. Every file is
staged and parsed, and the project file read by `plutil`, before any lands.

## In Craft

An app that uses Swift packages, as every Granite app does, builds only by a scheme: `xcodebuild` with no scheme
cannot resolve a package product. Craft's checks build an Xcode project with `xcodebuild build` unless the project
says otherwise, so give Craft the project's own command in its settings for the project (or for one run with
`CRAFT_CONFIG_OVERLAY`):

```json
{"build": {"command": "xcodebuild -scheme Hearth-macOS -destination platform=macOS build",
           "testCommand": "xcodebuild -scheme Hearth-macOS -destination platform=macOS test"}}
```

With no `team`, the Mac app is signed to run locally (ad hoc) and is the project's first target, so it builds and
runs on this Mac before a team is chosen. The UI tests are in the schemes but skipped until turned on, since they
need an interactive session to drive the app.

## Testing

```
swift test                     # the record, the schema, the lines, every make's files, the project file's edits
GRANITE_BUILD=1 swift test     # a recipe app made call by call, built and tested on macOS, built for the iOS
                               # simulator, its kit tested; Seer's shell (a default tab, two sheets, a sign-in
                               # gate) the same, and again with launch aliases, a sheet over a tab, a sheet over
                               # a sheet, the mark drawn as a tab's image, icon-only tabs, a tint, a tab change's
                               # impact, the first-run layer and the toast window, and again with sheets at their
                               # own heights (a medium one over a tab, a fraction one stacked on it); a fresh
                               # Xcode project linked, built and tested
```
