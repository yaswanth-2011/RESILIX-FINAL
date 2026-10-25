import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Runtime for Apple's on-device foundation models (AFM 3).
///
/// The framework is only present in the iOS 26 SDK and later. On older
/// systems the runtime reports itself as unavailable and the user is shown
/// the truthful reason instead of a silent fallback to a cloud service.
///
/// The session is held as `AnyObject` on purpose. `LanguageModelSession` is
/// annotated `@available(iOS 26.0, *)`, and a typed stored property would force
/// that availability onto this whole class (which the app-wide runtime list
/// needs on iOS 17), so the concrete type is only referenced inside
/// `#available` guards.
final class AppleFoundationModelRuntime: LocalModelRuntime {
    let runtimeName = L("Apple Foundation Models")

    private var task: Task<Void, Never>?

    #if canImport(FoundationModels)
    private var sessionBox: AnyObject?
    private var loadedIdentifier: String?
    #endif

    var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return true
            case .unavailable:
                return false
            }
        }
        return false
        #else
        return false
        #endif
    }

    var unavailableReason: String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(let reason):
                return String(describing: reason)
            }
        }
        return L("Apple Foundation Models require iOS 26 or later.")
        #else
        return L("The FoundationModels framework is not part of this build (iOS 26 SDK required).")
        #endif
    }

    var isLoaded: Bool {
        #if canImport(FoundationModels)
        return sessionBox != nil
        #else
        return false
        #endif
    }

    var loadedModelID: String? {
        #if canImport(FoundationModels)
        return loadedIdentifier
        #else
        return nil
        #endif
    }

    func load(model: LocalModelDescriptor, modelURL: URL?) async throws {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                let session = LanguageModelSession(instructions: L("You are the on-device assistant of the Resilix offline mesh app. Answer briefly and never invent emergency facts."))
                sessionBox = session
                loadedIdentifier = model.id
                return
            case .unavailable(let reason):
                throw LocalModelError.runtimeUnavailable(String(describing: reason))
            }
        }
        throw LocalModelError.runtimeUnavailable(L("Apple Foundation Models require iOS 26 or later."))
        #else
        throw LocalModelError.runtimeUnavailable(L("The FoundationModels framework is not part of this build."))
        #endif
    }

    func unload() {
        task?.cancel()
        task = nil
        #if canImport(FoundationModels)
        sessionBox = nil
        loadedIdentifier = nil
        #endif
    }

    func generate(request: LocalModelRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                guard let session = sessionBox as? LanguageModelSession else {
                    continuation.finish(throwing: LocalModelError.runtimeUnavailable(L("No model is loaded.")))
                    return
                }
                let work = Task {
                    do {
                        for try await response in session.streamResponse(to: request.prompt) {
                            if Task.isCancelled { break }
                            continuation.yield(response.content)
                        }
                        continuation.finish()
                    } catch {
                        if Task.isCancelled {
                            continuation.finish(throwing: LocalModelError.cancelled)
                        } else {
                            continuation.finish(throwing: LocalModelError.generationFailed(error.localizedDescription))
                        }
                    }
                }
                task = work
                continuation.onTermination = { _ in work.cancel() }
            } else {
                continuation.finish(throwing: LocalModelError.runtimeUnavailable(L("Apple Foundation Models require iOS 26 or later.")))
            }
            #else
            continuation.finish(throwing: LocalModelError.runtimeUnavailable(L("The FoundationModels framework is not part of this build.")))
            #endif
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
