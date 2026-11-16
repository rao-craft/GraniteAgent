import Foundation

/// Where the app shows its toasts.
public enum GraniteToasts: String, Codable, Sendable, CaseIterable {
    /// Over the root view, at its top, under a sheet or an alert that is up.
    case overlay
    /// On iOS in a window of their own one level above alerts (`.alert + 1`), over every sheet and alert, a touch
    /// anywhere but on a toast passing through to the app; the four styles in the system's circle symbols. The Mac
    /// keeps the overlay.
    case window
}
