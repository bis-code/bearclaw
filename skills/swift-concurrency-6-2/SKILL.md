---
name: swift-concurrency-6-2
description: Use for Swift 6.2 "Approachable Concurrency" — single-threaded by default, async stays on the calling actor (SE-0461), @concurrent for explicit background offloading, isolated conformances (SE-0470), MainActor-by-default (SE-0466). Triggers include data-race compiler errors, Xcode 26 migration, "where does this async run", or designing MainActor-centric app architecture.
---

# Swift 6.2 Approachable Concurrency

Swift 6.2 flips the default: code is **single-threaded (on the calling actor) unless you opt into parallelism**. This removes most spurious data-race errors while keeping the compile-time safety. These are the patterns for writing and migrating to it.

**Announce at start:** "I'm using the swift-concurrency-6-2 skill."

> **Verification note (2026-06-03):** the 6.2-specific surface below (`@concurrent`, `.defaultIsolation`, `NonisolatedNonsendingByDefault`, isolated conformances) is current as of Swift 6.2 / Xcode 26 but moves fast. **Confirm exact build-setting names against your installed toolchain** before relying on them — context7's Swift index still lags at 6.1.

## When to Activate

- Resolving "Sending 'self.x' risks causing data races" / data-race-safety errors
- Migrating Swift 5.x or 6.0/6.1 to 6.2 (Xcode 26)
- Deciding *where* an `async` function actually runs
- Designing a MainActor-centric app (most UI apps)
- Offloading genuinely CPU-heavy work (route/elevation compute, image processing)
- Making a `@MainActor` type conform to a non-isolated protocol

## The Mental Model (the one thing to internalize)

Before 6.2, a `nonisolated async` function was *implicitly* offloaded to a background thread, so even obviously-safe code tripped data-race errors. In 6.2 (SE-0461), **a nonisolated async function runs on the caller's actor by default** — it stays where it was called. Parallelism is now something you *ask for* (`@concurrent`), not something that happens to you.

## Pattern 1 — Async stays on the calling actor (SE-0461)

```swift
@MainActor
final class ChargerMapModel {
    let geocoder = Geocoder()   // non-Sendable, lives on the MainActor

    // Swift 6.1: ERROR — "Sending 'self.geocoder' risks causing data races"
    // Swift 6.2: OK — this async method stays on the MainActor
    func resolve(_ query: String) async throws -> [Charger] {
        let region = try await geocoder.region(for: query)  // still on MainActor
        return try await fetchChargers(in: region)
    }
}
```

No `@Sendable` wrappers, no `nonisolated` workarounds — the call chain simply stays put.

## Pattern 2 — `@concurrent` for genuine parallelism

When you *do* want work off the caller (CPU-bound, parallelizable), opt in explicitly. `@concurrent` requires a **nonisolated `async`** function, and its parameters/return must be `Sendable` (they cross to the concurrent pool).

```swift
nonisolated struct ElevationProcessor {
    // Heavy reduction — explicitly offloaded to the concurrent thread pool
    @concurrent
    static func computeProfile(from samples: [Sample]) async -> ElevationProfile {
        // expensive work over a large sample set…
    }
}

// Caller on the MainActor awaits; the work runs off the main actor.
let profile = await ElevationProcessor.computeProfile(from: samples)
```

To offload an existing function: (1) make it `nonisolated` (or put it in a nonisolated type), (2) add `@concurrent`, (3) ensure it's `async`, (4) `await` at call sites. **Profile first** — most async functions should *not* be `@concurrent`.

## Pattern 3 — Isolated conformances (SE-0470)

A `@MainActor` type can conform to a non-isolated protocol when the *conformance itself* is main-actor isolated:

```swift
protocol Exportable {
    func export() throws
}

@MainActor
final class RoutePlanModel {
    func makeGPX() -> String { /* reads main-actor state */ "" }
}

// The conformance is MainActor-isolated — usable only from the MainActor.
extension RoutePlanModel: @MainActor Exportable {
    func export() throws {
        let gpx = makeGPX()   // OK: same isolation
        // write gpx…
    }
}
```

The compiler enforces it: a `nonisolated` context cannot use a main-actor-isolated conformance. Prefer this over the older escape hatches (`@preconcurrency` conformance, `nonisolated func` that can't touch state, or making the requirement `async`) when the type is genuinely main-actor-bound.

## Pattern 4 — MainActor by default (SE-0466) + globals/statics

Global and `static` mutable state needs actor isolation or it's a data race:

```swift
// ERROR without isolation — shared mutable state
final class TripStore {
    static let shared = TripStore()   // Error: not concurrency-safe
    var trips: [Trip] = []
}
```

With **default MainActor isolation** enabled, types are implicitly `@MainActor`, so this just works — no per-declaration annotations:

```swift
// With `.defaultIsolation(MainActor.self)` — implicitly @MainActor:
final class TripStore {
    static let shared = TripStore()   // OK
    var trips: [Trip] = []
}
```

This mode is **opt-in and recommended for app/executable targets** (which are mostly single-threaded UI code). Library targets that need to run off the main actor should stay explicit.

## Enabling It (build settings)

**Xcode 26** — Build Settings → Swift Compiler:
- **Default Actor Isolation** = `MainActor` (SE-0466)
- **Approachable Concurrency** = `Yes` (umbrella that turns on the upcoming features, incl. `NonisolatedNonsendingByDefault`)

**SwiftPM** (`Package.swift`):

```swift
.target(
    name: "MyApp",
    swiftSettings: [
        .defaultIsolation(MainActor.self),                        // SE-0466
        .enableUpcomingFeature("NonisolatedNonsendingByDefault"), // SE-0461
    ]
)
```

Enable **incrementally** — one feature at a time — so each batch of newly-surfaced errors is small. The official migration tooling at swift.org/migration can apply many changes automatically.

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| Single-threaded by default | The natural way to write code is data-race-free; concurrency is opt-in |
| Async stays on the caller (SE-0461) | Kills the implicit offloading that caused spurious data-race errors |
| `@concurrent` is explicit | Background execution is a deliberate perf choice, never accidental |
| Isolated conformances (SE-0470) | MainActor types conform to plain protocols without unsafe workarounds |
| MainActor-by-default (SE-0466) | Removes annotation noise for app targets that are mostly UI |
| Opt-in adoption | Non-breaking, incremental migration path |

## Best Practices

- **Start on the MainActor.** Write single-threaded code first; offload only measured hot paths.
- **Use `@concurrent` only for CPU-bound work** (route/elevation math, compression, image processing) — and **profile with Instruments first**.
- **Enable MainActor-default inference** for app targets; keep libraries explicit.
- **Reach for isolated conformances** instead of `nonisolated`/`@preconcurrency` band-aids when a type is genuinely main-actor-bound.
- **Protect globals/statics** with actor isolation.

## Anti-Patterns

- `@concurrent` on every `async` function (most don't need a background thread).
- Sprinkling `nonisolated` to silence the compiler without understanding the isolation it removes.
- Keeping legacy `DispatchQueue`/`NSLock` where an actor gives the same safety with less code.
- Assuming all `async` runs in the background — in 6.2 it stays on the caller by default.
- Fighting the compiler: a reported data race is almost always a real one.

## Related

- **`swift-actor-persistence`** — actor-based storage layer; the offline cache an app on this model uses.
- **`swift-protocol-di-testing`** — making the above testable with focused protocols + Swift Testing.
- **`swift-reviewer`** agent — review Swift diffs against these isolation rules.
