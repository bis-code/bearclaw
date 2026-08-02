---
name: swift-protocol-di-testing
description: Use for protocol-based dependency injection that makes Swift code testable — abstract file system, network, and external APIs behind small focused protocols, inject via default parameters, and test with Swift Testing (@Test/@Suite/#expect/#require). Triggers include testing error paths without real I/O, mocking boundaries, or designing testable architecture with actors/Sendable.
---

# Swift Protocol-Based Dependency Injection for Testing

Make code testable by hiding external dependencies (file system, network, iCloud) behind **small, single-purpose protocols**. Production uses real implementations via default parameters; tests inject mocks — no real I/O, deterministic error paths.

**Announce at start:** "I'm using the swift-protocol-di-testing skill."

## When to Activate

- Code touches the file system, network, or external APIs
- Need to test error-handling paths that are hard to trigger for real
- Modules that must run in app, test, *and* SwiftUI preview contexts
- Testable architecture under Swift concurrency (actors, `Sendable`)

## 1. Define small, focused protocols (one concern each)

```swift
public protocol FileAccessing: Sendable {
    func read(from url: URL) throws -> Data
    func write(_ data: Data, to url: URL) throws
    func fileExists(at url: URL) -> Bool
}
```

## 2. Production implementation

```swift
public struct DefaultFileAccessor: FileAccessing {
    public init() {}
    public func read(from url: URL) throws -> Data { try Data(contentsOf: url) }
    public func write(_ data: Data, to url: URL) throws { try data.write(to: url, options: .atomic) }
    public func fileExists(at url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path) }
}
```

## 3. Mock with configurable failures

```swift
public final class MockFileAccessor: FileAccessing, @unchecked Sendable {
    public var files: [URL: Data] = [:]
    public var readError: Error?
    public var writeError: Error?
    public init() {}

    public func read(from url: URL) throws -> Data {
        if let readError { throw readError }
        guard let data = files[url] else { throw CocoaError(.fileReadNoSuchFile) }
        return data
    }
    public func write(_ data: Data, to url: URL) throws {
        if let writeError { throw writeError }
        files[url] = data
    }
    public func fileExists(at url: URL) -> Bool { files[url] != nil }
}
```

`@unchecked Sendable` is acceptable here because the mock is confined to a single test; for parallel-test safety, make it an `actor` instead.

## 4. Inject via default parameters

Production gets the real implementation for free; only tests pass a mock.

```swift
public actor SyncManager {
    private let files: FileAccessing
    public init(files: FileAccessing = DefaultFileAccessor()) { self.files = files }

    public func load(from url: URL) throws -> Data {
        guard files.fileExists(at: url) else { throw SyncError.missingFile }
        return try files.read(from: url)
    }
}
```

## 5. Test with Swift Testing

Group with `@Suite`, assert with `#expect`, unwrap-or-fail with `#require`, and check error paths with `#expect(throws:)` (prefix `await` for async):

```swift
import Testing

@Suite("SyncManager")
struct SyncManagerTests {
    let url = URL(filePath: "/tmp/data.json")

    @Test("reads stored data")
    func readsData() async throws {
        let mock = MockFileAccessor()
        mock.files[url] = Data("hello".utf8)
        let manager = SyncManager(files: mock)

        let data = try await manager.load(from: url)
        let text = try #require(String(data: data, encoding: .utf8))   // unwrap or fail
        #expect(text == "hello")
    }

    @Test("missing file throws")
    func missingFile() async {
        let manager = SyncManager(files: MockFileAccessor())   // empty
        await #expect(throws: SyncError.missingFile) {
            try await manager.load(from: url)
        }
    }

    @Test("surfaces read errors")
    func readError() async {
        let mock = MockFileAccessor()
        mock.files[url] = Data()
        mock.readError = CocoaError(.fileReadCorruptFile)
        let manager = SyncManager(files: mock)

        await #expect(throws: CocoaError.self) {
            try await manager.load(from: url)
        }
    }
}
```

## Best Practices

- **One concern per protocol** — no "god protocols" with a dozen methods.
- **`Sendable` conformance** when the protocol crosses actor boundaries.
- **Default parameters** so production never mentions mocks.
- **Configurable error properties** on mocks to exercise failure paths.
- **Mock only boundaries** (file system, network, APIs) — never internal types.
- **`try #require`** to unwrap optionals in tests (fails clearly) rather than force-unwrap.

## Anti-Patterns

- One large protocol covering every external access.
- Mocking internal types that have no external dependency.
- `#if DEBUG` switches instead of real injection.
- Forgetting `Sendable` when used with actors.
- Over-engineering: a type with no external dependency needs no protocol.

## Related

- **`swift-actor-persistence`** — inject a `MockFileAccessor` to test that actor repository without disk.
- **`swift-concurrency-6-2`** — the `Sendable`/actor rules these protocols must satisfy.
- **`swift-reviewer`** agent — review test design and mock boundaries.
