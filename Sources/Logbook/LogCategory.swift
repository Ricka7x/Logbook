import Foundation

/// A named bucket for grouping related log lines (e.g. "networking", "sync",
/// "windowSnapping"). A plain string wrapper (same shape as `Notification.Name`)
/// rather than a fixed enum, since each app using this package has its own set of
/// features and shouldn't need to fork this package to add one.
///
/// Define your app's categories as static constants in your own code:
///
///     extension LogCategory {
///         static let sync = LogCategory("sync")
///         static let importing = LogCategory("importing")
///     }
public struct LogCategory: RawRepresentable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// Used when a call site doesn't pass a category and none can be inferred.
    public static let general = LogCategory("general")
}
