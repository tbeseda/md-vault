import CoreServices
import Foundation

// FSEvents provides recursive watching without one file descriptor per folder.
@MainActor
final class VaultWatcher {
    let events: AsyncStream<[String]>
    private let continuation: AsyncStream<[String]>.Continuation
    private let stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.tbeseda.md-vault.watcher")

    fileprivate final class ContinuationBox: Sendable {
        let continuation: AsyncStream<[String]>.Continuation
        init(_ continuation: AsyncStream<[String]>.Continuation) { self.continuation = continuation }
    }

    init(vaultURL: URL) {
        (events, continuation) = AsyncStream.makeStream(of: [String].self)
        let box = ContinuationBox(continuation)

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(box).toOpaque(),
            retain: nil,
            release: releaseWatcherInfo,
            copyDescription: nil
        )
        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            handleWatcherEvents,
            &context,
            [vaultURL.path(percentEncoded: false)] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )
        if let stream {
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
        }
    }

    func stop() {
        continuation.finish()
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
    }
}

// File-scope callbacks avoid inheriting the watcher's main-actor isolation.

private func handleWatcherEvents(
    _ stream: ConstFSEventStreamRef,
    _ info: UnsafeMutableRawPointer?,
    _ eventCount: Int,
    _ eventPaths: UnsafeMutableRawPointer,
    _ eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    _ eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info else { return }
    let box = Unmanaged<VaultWatcher.ContinuationBox>.fromOpaque(info).takeUnretainedValue()
    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
    box.continuation.yield(paths)
}

private func releaseWatcherInfo(_ info: UnsafeRawPointer?) {
    guard let info else { return }
    Unmanaged<VaultWatcher.ContinuationBox>.fromOpaque(info).release()
}
