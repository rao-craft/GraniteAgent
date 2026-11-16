import Foundation

/// A height a sheet rests at, as a destinations line names it after `detents`: `medium`, `large`, `fraction(0.6)` (a
/// share of the screen's height) or `height(320)` (points). The first a line names is where the sheet goes up, on a
/// launch too; the person drags it between them.
enum SheetDetent: Equatable, Sendable {
    case medium, large
    /// A share of the screen's height, above 0 and at most 1.
    case fraction(Double)
    /// A height in points, above 0.
    case height(Double)

    /// The heights a line may name, as a refusal shows them.
    static let forms = "`medium`, `large`, `fraction(0.6)` or `height(320)`"

    /// The height a word names, as the line says it; nil when it names none. A value out of range is read, and
    /// `problem` says what is wrong with it.
    init?(word: String) {
        switch word {
        case "medium": self = .medium
        case "large": self = .large
        default:
            for kind in ["fraction", "height"] where word.hasPrefix(kind + "(") && word.hasSuffix(")") {
                let number = word.dropFirst(kind.count + 1).dropLast()
                guard number.range(of: #"^([0-9]+(\.[0-9]+)?|\.[0-9]+)$"#, options: .regularExpression) != nil, let value = Double(number) else { return nil }
                self = kind == "fraction" ? .fraction(value) : .height(value)
                return
            }
            return nil
        }
    }

    /// What is wrong with the value it holds: a share of the screen above 1 or at 0, or no height at all.
    var problem: String? {
        switch self {
        case .medium, .large: nil
        case .fraction(let share): share > 0 && share <= 1 ? nil : "a fraction is a share of the screen's height, above 0 and at most 1, like `fraction(0.6)`"
        case .height(let points): points > 0 ? nil : "a height is in points, above 0, like `height(320)`"
        }
    }

    /// As a line says it: `medium`, `fraction(0.6)`, `height(320)`.
    var word: String {
        switch self {
        case .medium: "medium"
        case .large: "large"
        case .fraction(let share): "fraction(\(Self.number(share)))"
        case .height(let points): "height(\(Self.number(points)))"
        }
    }

    /// As SwiftUI writes it: `.medium`, `.fraction(0.6)`, `.height(320)`.
    var swift: String { "." + word }

    /// A number as Swift writes it short: `320` for 320.0, `0.6` for 0.6.
    private static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int(value)) : String(value)
    }
}
