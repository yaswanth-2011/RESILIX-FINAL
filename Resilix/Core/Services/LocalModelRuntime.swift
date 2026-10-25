import Foundation

/// Common interface of the local inference runtimes.
///
/// Every runtime streams its answer token by token and can be stopped with
/// `cancel()`. Only one model may be loaded at a time (see
/// `LocalAIService`) so that the memory usage stays predictable on older
/// devices.
protocol LocalModelRuntime: AnyObject {
    /// Name of the runtime, e.g. L("Apple Foundation Models").
    var runtimeName: String { get }
    /// `true` when the runtime can be used on this device.
    var isAvailable: Bool { get }
    /// Explanation when the runtime cannot be used.
    var unavailableReason: String? { get }
    /// `true` while a model is loaded.
    var isLoaded: Bool { get }
    /// The model that is currently loaded.
    var loadedModelID: String? { get }

    func load(model: LocalModelDescriptor, modelURL: URL?) async throws
    func unload()
    /// Streams the answer of the model.
    func generate(request: LocalModelRequest) -> AsyncThrowingStream<String, Error>
    /// Stops the current generation.
    func cancel()
}

/// A runtime that streams everything it is given - used when no real
/// inference runtime is linked into the build. It never pretends to be an
/// AI: the service reports the missing runtime instead of using it.
final class UnavailableModelRuntime: LocalModelRuntime {
    let runtimeName: String
    private let reason: String

    init(runtimeName: String, reason: String) {
        self.runtimeName = runtimeName
        self.reason = reason
    }

    var isAvailable: Bool { false }
    var isLoaded: Bool { false }
    var loadedModelID: String? { nil }

    /// Matches the optional requirement of `LocalModelRuntime` exactly.
    var unavailableReason: String? { reason }

    func load(model: LocalModelDescriptor, modelURL: URL?) async throws {
        throw LocalModelError.runtimeUnavailable(reason)
    }

    func unload() {}

    func generate(request: LocalModelRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LocalModelError.runtimeUnavailable(reason))
        }
    }

    func cancel() {}
}
