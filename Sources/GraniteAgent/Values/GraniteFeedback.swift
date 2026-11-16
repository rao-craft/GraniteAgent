import Foundation

/// The impact a change gives, as UIKit's impact generator names its styles.
public enum GraniteFeedback: String, Codable, Sendable, CaseIterable {
    case light, medium, heavy, soft, rigid

    /// The SwiftUI feedback that gives it: `.impact(weight: .light)`, `.impact(flexibility: .soft)`.
    var sensory: String {
        switch self {
        case .light, .medium, .heavy: ".impact(weight: .\(rawValue))"
        case .soft, .rigid: ".impact(flexibility: .\(rawValue))"
        }
    }
}
