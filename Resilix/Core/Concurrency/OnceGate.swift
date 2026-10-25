import Foundation

/// A one-shot gate for callbacks that can arrive from several threads.
///
/// `NWConnection.stateUpdateHandler`, `NWBrowser.stateUpdateHandler` and the
/// timeouts that race against them all need the same guarantee: the *first*
/// outcome wins and every later caller stands down. A captured `var` cannot
/// express that — Swift 6 rejects mutating a captured variable from a
/// concurrently executing closure — so the flag lives behind a lock here.
final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    /// Claims the gate. Returns `true` for exactly one caller.
    func claim() -> Bool {
        lock.withLock {
            if claimed { return false }
            claimed = true
            return true
        }
    }

    /// Whether the gate has already been claimed.
    var isClaimed: Bool {
        lock.withLock { claimed }
    }
}
