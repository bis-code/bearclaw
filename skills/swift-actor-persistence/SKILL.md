---
name: swift-actor-persistence
description: Use for thread-safe data persistence in Swift via actors — an in-memory cache with file-backed storage that eliminates data races by design. Triggers include building an offline-first store/repository, replacing DispatchQueue/NSLock synchronization, or needing concurrent-safe access to shared mutable state.
---

# Swift Actors for Thread-Safe Persistence

Build a persistence layer as an `actor`: the compiler serializes all access, so there are no data races and no manual locks. Pair an in-memory cache (fast reads) with atomic file writes (durability).

**Announce at start:** "I'm using the swift-actor-persistence skill."

## When to Activate

- Building a data persistence / repository layer (Swift 5.5+)
- Offline-first apps with local storage that sync later
- Need thread-safe access to shared mutable state
- Replacing `DispatchQueue`/`NSLock` synchronization with modern concurrency

## Core Pattern — Actor-Based Repository

```swift
public actor LocalRepository<T: Codable & Identifiable & Sendable> where T.ID == String {
    private var cache: [String: T] = [:]
    private let fileURL: URL

    public init(directory: URL = .documentsDirectory, filename: String = "data.json") {
        self.fileURL = directory.appendingPathComponent(filename)
        // Synchronous load during init — actor isolation isn't active yet, so this is safe.
        self.cache = Self.loadSynchronously(from: fileURL)
    }

    // MARK: Public API (domain operations only)
    public func save(_ item: T) throws { cache[item.id] = item; try persist() }
    public func delete(_ id: String) throws { cache[id] = nil; try persist() }
    public func find(by id: String) -> T? { cache[id] }
    public func loadAll() -> [T] { Array(cache.values) }

    // MARK: Private
    private func persist() throws {
        let data = try JSONEncoder().encode(Array(cache.values))
        try data.write(to: fileURL, options: .atomic)   // crash-safe
    }

    private static func loadSynchronously(from url: URL) -> [String: T] {
        guard let data = try? Data(contentsOf: url),
              let items = try? JSONDecoder().decode([T].self, from: data) else { return [:] }
        return Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }
}
```

Every call is `await`ed because the actor isolates its state:

```swift
let repo = LocalRepository<Trip>()
let trip = await repo.find(by: "t-001")     // O(1) cache hit
try await repo.save(newTrip)                // updates cache + atomic file write
```

## Combining with an @Observable view model

Under Swift 6.2's MainActor-by-default (see `swift-concurrency-6-2`), the view model is main-actor-isolated; it `await`s the actor and republishes for the UI:

```swift
@Observable
final class TripListModel {
    private(set) var trips: [Trip] = []
    private let repo: LocalRepository<Trip>

    init(repo: LocalRepository<Trip> = LocalRepository()) { self.repo = repo }

    func load() async { trips = await repo.loadAll() }
    func add(_ trip: Trip) async throws {
        try await repo.save(trip)
        trips = await repo.loadAll()
    }
}
```

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Actor, not class + lock | Compiler-enforced thread safety, zero manual synchronization |
| In-memory cache + file persistence | Fast reads from RAM, durable writes to disk |
| Synchronous `init` load | Avoids async-init complexity for small local files |
| Dictionary keyed by `ID` | O(1) lookups |
| Generic over `Codable & Identifiable & Sendable` | Reusable; `Sendable` so values cross the actor boundary safely |
| `.atomic` writes | No partial files if the app crashes mid-write |

## Best Practices

- **`Sendable` element types** — required for anything crossing the actor boundary.
- **Keep the public API to domain operations** — never expose the internal cache dictionary.
- **`.atomic` writes** to prevent corruption on crash.
- **Load synchronously in `init`** for local files — async init adds complexity for little gain.
- **Pair with an `@Observable` view model** for reactive UI.

## Anti-Patterns

- `DispatchQueue`/`NSLock` for *new* concurrency code — use the actor.
- Exposing the internal cache to callers (breaks the isolation guarantee).
- `nonisolated` to bypass isolation (defeats the purpose).
- Forgetting that every actor method is `await` — callers need an async context.
- Unbounded growth: for large datasets, page or stream instead of holding everything in `cache`.

## Related

- **`swift-concurrency-6-2`** — the isolation model this builds on; where `await`/actor rules come from.
- **`swift-protocol-di-testing`** — inject a mock file accessor to unit-test this repository without touching disk.
- **`swift-reviewer`** agent — review the persistence layer for isolation/`Sendable` issues.
