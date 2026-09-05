# Logbook

A small, dependency-free logger for macOS/iOS apps: level and category filtering, a
queryable in-memory ring buffer for building a diagnostics/export view, and settings
that persist across launches. No `os_log`/Console.app tie-in. Just `print` plus a
buffer you can filter, so behavior is identical in every app that adopts it.

## Usage

Define your app's own categories. `LogCategory` is an open string wrapper, not a
fixed enum, so adding a category never means touching this package:

```swift
import Logbook

extension LogCategory {
    static let sync = LogCategory("sync")
    static let importing = LogCategory("importing")
}
```

Log from anywhere:

```swift
Logbook.shared.info("Starting sync", service: "SyncEngine", category: .sync)
Logbook.shared.error("Sync failed: \(error)", service: "SyncEngine", category: .sync)
```

`message` is `@autoclosure`, so string interpolation only runs when the line will
actually be emitted. String-building work is never paid for behind a disabled
category or a filtered-out level.

For diagnostic work that isn't expressible as a single expression (a multi-line report
built in a loop, say), gate it explicitly instead:

```swift
if Logbook.shared.willLog(level: .debug, category: .sync) {
    Logbook.shared.debug(buildExpensiveReport(), service: "SyncEngine", category: .sync)
}
```

## Settings

```swift
Logbook.shared.isEnabled = true          // global on/off (debug: true, release: false, by default)
Logbook.shared.minimumLevel = .warning   // debug/info/warning/error
Logbook.shared.disable(.sync)            // silence one category; all categories are enabled by default
Logbook.shared.enable(.sync)
Logbook.shared.enableAllCategories()
```

Settings persist in `UserDefaults.standard` by default, namespaced under the
`Logbook.` key prefix so they never collide with the host app's own keys. Listen for
`Logbook.settingsChangedNotification` to react live in a Settings screen.

## Diagnostics export

```swift
let lines = Logbook.shared.recentLogs(minimumLevel: .warning, limit: 50)
// ["⚠️ [2026-01-01T00:00:00.000Z] [SyncEngine] [sync] Retry scheduled", ...]
```

Backed by an in-memory ring buffer (default 500 entries, configurable via
`Logbook(maxRecentEntries:)`). Good for a "copy diagnostics" button or an in-app log
viewer; it does not persist across launches.

## Multiple instances

`Logbook.shared` covers the common case of one logger per app. If you need a second,
independent instance (rare), give it its own `subsystem` so its settings don't collide
with the shared one:

```swift
let importLogger = Logbook(subsystem: "Logbook.import")
```

## Adding to a project

```swift
.package(url: "https://github.com/Ricka7x/Logbook", from: "1.0.0")
```

Or, for local development against a sibling checkout instead of a published tag:

```swift
.package(path: "../Logbook")
```
