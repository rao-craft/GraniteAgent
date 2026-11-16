import Foundation

/// The font design the toasts' text takes in their own window (`toasts: window`): the system's when left out.
public enum GraniteToastDesign: String, Codable, Sendable, CaseIterable {
    case serif
    case rounded
    case monospaced
}
