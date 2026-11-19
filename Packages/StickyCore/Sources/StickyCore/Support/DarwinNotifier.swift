import CoreFoundation
import Foundation

/// Cross-process "the store changed" signal via the Darwin notify center.
/// Darwin notifications carry no payload, so nothing sensitive can leak through them.
public enum DarwinNotifier {
    public static let storeChanged = "com.jfzepeda.stickydesk.store-changed"

    public static func post(_ name: String = storeChanged) {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(name as CFString),
            nil, nil, true
        )
    }
}

/// Keeps a Darwin notification observation alive until `cancel()` or deinit.
public final class DarwinObservation: @unchecked Sendable {
    // @unchecked: `handler` and `name` are immutable after init; registration and
    // removal go through CFNotificationCenter, which is thread-safe.
    private let name: String
    private let handler: @Sendable () -> Void
    private let lock = NSLock()
    private var isActive = false

    /// The handler runs on whatever thread CoreFoundation delivers on; hop to your actor.
    public init(name: String = DarwinNotifier.storeChanged, handler: @escaping @Sendable () -> Void) {
        self.name = name
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                Unmanaged<DarwinObservation>.fromOpaque(observer).takeUnretainedValue().handler()
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
        isActive = true
    }

    public func cancel() {
        lock.lock()
        defer { lock.unlock() }
        guard isActive else { return }
        isActive = false
        CFNotificationCenterRemoveObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            Unmanaged.passUnretained(self).toOpaque(),
            CFNotificationName(name as CFString),
            nil
        )
    }

    deinit { cancel() }
}
