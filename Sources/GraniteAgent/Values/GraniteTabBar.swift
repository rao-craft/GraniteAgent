import Foundation

/// What a tab bar item shows.
public enum GraniteTabBar: String, Codable, Sendable, CaseIterable {
    /// The tab's image over its title (when left out).
    case labels
    /// The tab's image alone, as `Tab("", …)` draws it: an empty title.
    case icons
}
