import Foundation

/// Another name a launch may give, as a destinations line says it: `auth.signup -> auth`. A launch with
/// `-destination auth.signup` opens what `-destination auth` opens (the tab selected, the sheet up, the gate shown or
/// passed), and the name stays in the `destination` default for the page to read and open its own inner state.
struct LaunchAlias: Equatable, Sendable {
    /// The name a launch gives: any destination name, dots allowed (`settings.feedback`).
    var name: String
    /// What it opens: a destination's case, or another alias (read through to its destination before it is written).
    var target: String
    /// The height a launch with it puts its sheet up at, in place of the sheet's first, as its line names it after the
    /// destination (`world.full -> world large`); nil for the sheet's first, or the height of the alias it names.
    var detent: SheetDetent?

    /// Whether `text` is a name a launch may give: letters, digits and `_`, in parts joined by `.` or `-`.
    static func isName(_ text: String) -> Bool {
        text.range(of: #"^[A-Za-z0-9_]+([.-][A-Za-z0-9_]+)*$"#, options: .regularExpression) != nil
    }
}
