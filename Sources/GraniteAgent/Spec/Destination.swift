import Foundation

/// One of the app's destinations, as a destinations line says it: `feed: Feed "Feed" house`.
struct Destination: Equatable, Sendable {
    /// Where a destination sits: a tab (in the tab bar and the sidebar), a sheet over the tabs, or the gate shown
    /// instead of them while the call's `gate` holds.
    enum Place: String, Equatable, Sendable {
        case tab, sheet, gate
    }

    /// The case of `AppDestination`.
    var name: String
    /// The view it shows: `Feed()` or `Feed(kind: .all)`.
    var view: String
    /// The view's type.
    var viewType: String
    var title: String
    var symbol: String
    /// The view the detail pane shows beside it, in the split style.
    var detail: String?
    var detailType: String?
    /// A tab unless its line says `sheet` or `gate` after the symbol.
    var place: Place = .tab
    /// Whether its line says `default`: the tab a plain launch opens on, instead of the first.
    var isDefault = false
}
