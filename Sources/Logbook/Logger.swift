import Foundation

/// A lightweight, filterable logger: level and category gating, an in-memory ring
/// buffer for pulling up recent activity in a diagnostics view, and settings that
/// persist across launches. No third-party dependencies, no `os_log`/Console.app
/// tie-in. Just `print` plus a queryable buffer, so it behaves identically in every
/// app that adopts it.
///
/// Typical usage: one shared instance per app, categories defined by that app.
///
///     extension LogCategory {
///         static let sync = LogCategory("sync")
///     }
///
///     Logbook.shared.info("Starting sync", service: "SyncEngine", category: .sync)
///     Logbook.shared.error("Sync failed: \(error)", service: "SyncEngine", category: .sync)
///
/// `message` is `@autoclosure`, so string interpolation only runs when the line will
/// actually be emitted. String-building work is never paid for behind a disabled
/// category or a filtered-out level.
public final class Logbook: @unchecked Sendable {
    public static let shared = Logbook()

    public struct Entry: Sendable {
        public let timestamp: Date
        public let level: LogLevel
        public let service: String
        public let category: LogCategory
        public let message: String
    }

    /// Posted whenever `isEnabled`, `minimumLevel`, or a category's enabled state
    /// changes. Lets a Settings screen built on this logger react live without
    /// polling. `object` is the `Logbook` instance that changed.
    public static let settingsChangedNotification = Notification.Name("Logbook.settingsChanged")

    private enum Keys {
        static let isEnabled = "isEnabled"
        static let minimumLevel = "minimumLevel"
        static let disabledCategories = "disabledCategories"
    }

    private let defaults: UserDefaults
    /// Every persisted key is namespaced under this so a logger's settings can never
    /// collide with the host app's own `UserDefaults.standard` keys.
    private let keyPrefix: String
    private let maxRecentEntries: Int
    private let stateQueue: DispatchQueue

    private var recentEntries: [Entry] = []

    /// - Parameters:
    ///   - defaults: Where settings persist. Defaults to `.standard`, which is already
    ///     scoped per-app by bundle ID. Pass a custom suite only if you want a second,
    ///     independent logger instance within the same app.
    ///   - subsystem: Namespaces this instance's settings keys. Only needed if you're
    ///     running more than one `Logbook` instance against the same `UserDefaults`.
    ///   - maxRecentEntries: Size of the in-memory ring buffer `recentLogs` reads from.
    public init(defaults: UserDefaults = .standard, subsystem: String = "Logbook", maxRecentEntries: Int = 500) {
        self.defaults = defaults
        self.keyPrefix = subsystem
        self.maxRecentEntries = maxRecentEntries
        self.stateQueue = DispatchQueue(label: "\(subsystem).state")
    }

    // MARK: - Settings

    /// Whether logging is on at all. Defaults to `true` in debug builds, `false` in
    /// release. Most apps don't want a release build silently printing to a console
    /// nobody's attached to, but do want it available to flip on for diagnosing a
    /// specific user's report.
    public var isEnabled: Bool {
        get {
            stateQueue.sync {
                if defaults.object(forKey: key(Keys.isEnabled)) != nil {
                    return defaults.bool(forKey: key(Keys.isEnabled))
                }
                #if DEBUG
                    return true
                #else
                    return false
                #endif
            }
        }
        set {
            stateQueue.sync { defaults.set(newValue, forKey: key(Keys.isEnabled)) }
            postSettingsChanged()
        }
    }

    /// Entries below this level are dropped before `message` is even evaluated.
    public var minimumLevel: LogLevel {
        get {
            stateQueue.sync {
                if let raw = defaults.object(forKey: key(Keys.minimumLevel)) as? Int,
                    let level = LogLevel(rawValue: raw)
                {
                    return level
                }
                #if DEBUG
                    return .debug
                #else
                    return .warning
                #endif
            }
        }
        set {
            stateQueue.sync { defaults.set(newValue.rawValue, forKey: key(Keys.minimumLevel)) }
            postSettingsChanged()
        }
    }

    /// Categories are enabled by default. This is a blocklist, not an allowlist,
    /// since categories are an open set (see `LogCategory`) with no fixed universe to
    /// default an allowlist to.
    private var disabledCategories: Set<String> {
        get {
            stateQueue.sync { Set(defaults.stringArray(forKey: key(Keys.disabledCategories)) ?? []) }
        }
        set {
            stateQueue.sync { defaults.set(Array(newValue), forKey: key(Keys.disabledCategories)) }
        }
    }

    public func isCategoryEnabled(_ category: LogCategory) -> Bool {
        !disabledCategories.contains(category.rawValue)
    }

    public func disable(_ category: LogCategory) {
        var categories = disabledCategories
        categories.insert(category.rawValue)
        disabledCategories = categories
        postSettingsChanged()
    }

    public func enable(_ category: LogCategory) {
        var categories = disabledCategories
        categories.remove(category.rawValue)
        disabledCategories = categories
        postSettingsChanged()
    }

    /// Re-enables every category previously silenced with `disable(_:)`.
    public func enableAllCategories() {
        disabledCategories = []
        postSettingsChanged()
    }

    private func postSettingsChanged() {
        NotificationCenter.default.post(name: Self.settingsChangedNotification, object: self)
    }

    // MARK: - Logging

    /// Returns `true` when a message at `level`/`category` would actually be emitted.
    /// Use this to gate diagnostic work that isn't expressible as a single
    /// `@autoclosure` (e.g. a multi-line string built in a loop):
    ///
    ///     if logger.willLog(level: .debug, category: .sync) {
    ///         logger.debug(buildExpensiveReport(), service: "SyncEngine", category: .sync)
    ///     }
    public func willLog(level: LogLevel, category: LogCategory) -> Bool {
        guard isEnabled, level >= minimumLevel else { return false }
        return isCategoryEnabled(category)
    }

    /// The core logging call. `debug`/`info`/`warning`/`error` below all forward here.
    public func log(
        _ message: @autoclosure () -> String,
        level: LogLevel = .info,
        service: String,
        category: LogCategory = .general
    ) {
        guard willLog(level: level, category: category) else { return }

        let resolvedMessage = message()
        let now = Date()
        print(formattedLine(timestamp: now, level: level, service: service, category: category, message: resolvedMessage))

        stateQueue.sync {
            recentEntries.append(
                Entry(timestamp: now, level: level, service: service, category: category, message: resolvedMessage))
            if recentEntries.count > maxRecentEntries {
                recentEntries.removeFirst(recentEntries.count - maxRecentEntries)
            }
        }
    }

    public func debug(_ message: @autoclosure () -> String, service: String, category: LogCategory = .general) {
        log(message(), level: .debug, service: service, category: category)
    }

    public func info(_ message: @autoclosure () -> String, service: String, category: LogCategory = .general) {
        log(message(), level: .info, service: service, category: category)
    }

    public func warning(_ message: @autoclosure () -> String, service: String, category: LogCategory = .general) {
        log(message(), level: .warning, service: service, category: category)
    }

    public func error(_ message: @autoclosure () -> String, service: String, category: LogCategory = .general) {
        log(message(), level: .error, service: service, category: category)
    }

    // MARK: - Export / diagnostics

    /// Recently captured lines, most-recent-last, formatted the same as what's printed.
    /// Meant for a user-facing "export diagnostics" action or an in-app log viewer,
    /// not for reconstructing structured data (use the `Entry` buffer directly for
    /// that, if you expose it).
    public func recentLogs(
        minimumLevel: LogLevel = .warning,
        categories: Set<LogCategory>? = nil,
        service: String? = nil,
        search: String? = nil,
        limit: Int = 30
    ) -> [String] {
        stateQueue.sync {
            recentEntries
                .filter { $0.level >= minimumLevel }
                .filter { categories == nil || categories!.contains($0.category) }
                .filter { service == nil || $0.service == service }
                .filter { search == nil || $0.message.localizedCaseInsensitiveContains(search!) }
                .suffix(max(0, limit))
                .map { formattedLine(timestamp: $0.timestamp, level: $0.level, service: $0.service, category: $0.category, message: $0.message, isoTimestamp: true) }
        }
    }

    private func formattedLine(
        timestamp: Date, level: LogLevel, service: String, category: LogCategory, message: String,
        isoTimestamp: Bool = false
    ) -> String {
        let time =
            isoTimestamp
            ? Self.isoFormatter.string(from: timestamp)
            : Self.timeFormatter.string(from: timestamp)
        return "\(level.prefix) [\(time)] [\(service)] [\(category.rawValue)] \(message)"
    }

    private func key(_ suffix: String) -> String {
        "\(keyPrefix).\(suffix)"
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
