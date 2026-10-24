import Foundation

#if canImport(LiteRTLM)
import LiteRTLM
#endif

/// Runtime for Google's LiteRT-LM (Gemma 4 E2B, Qwen3-0.6B).
///
/// The runtime is only active when the `LiteRTLM` Swift package is linked
/// into the build (`#if canImport(LiteRTLM)`). Without the package the
/// runtime reports itself as unavailable, the model catalogue still shows
/// the exact model identifiers and the app never falls back to a cloud
/// service.
final class LiteRTModelRuntime: LocalModelRuntime {
    let runtimeName = "LiteRT-LM"

    private var task: Task<Void, Never>?
    private var loadedIdentifier: String?

    #if canImport(LiteRTLM)
    private var engine: Engine?
    private var conversation: Conversation?
    #endif

    var isAvailable: Bool {
        #if canImport(LiteRTLM)
        return true
        #else
        return false
        #endif
    }

    var unavailableReason: String? {
        #if canImport(LiteRTLM)
        return nil
        #else
        return "The LiteRT-LM package (github.com/google-ai-edge/LiteRT-LM) is not linked into this build."
        #endif
    }

    var isLoaded: Bool {
        #if canImport(LiteRTLM)
        return engine != nil
        #else
        return false
        #endif
    }

    var loadedModelID: String? { loadedIdentifier }

    func load(model: LocalModelDescriptor, modelURL: URL?) async throws {
        #if canImport(LiteRTLM)
        guard let modelURL else {
            throw LocalModelError.modelNotInstalled(model.displayName)
        }
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw LocalModelError.modelNotInstalled(model.displayName)
        }
        unload()
        let cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("litert-cache-\(model.id)", isDirectory: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        let configuration: EngineConfig
        do {
            configuration = try EngineConfig(modelPath: modelURL.path,
                                            backend: .cpu(),
                                            maxNumTokens: 512,
                                            cacheDir: cacheDirectory.path)
        } catch {
            throw LocalModelError.runtimeUnavailable(error.localizedDescription)
        }
        let engine = Engine(engineConfig: configuration)
        do {
            try await engine.initialize()
        } catch {
            throw LocalModelError.runtimeUnavailable(error.localizedDescription)
        }
        let conversationConfiguration = ConversationConfig(
            systemMessage: Message("You are the on-device assistant of the Resilix offline mesh app. Answer briefly and never invent emergency facts."),
            samplerConfig: try SamplerConfig(topK: 40, topP: 0.95, temperature: 0.7)
        )
        let conversation = try await engine.createConversation(with: conversationConfiguration)
        self.engine = engine
        self.conversation = conversation
        loadedIdentifier = model.id
        #else
        throw LocalModelError.runtimeUnavailable(unavailableReason ?? "runtime missing")
        #endif
    }

    func unload() {
        task?.cancel()
        task = nil
        #if canImport(LiteRTLM)
        conversation = nil
        engine = nil
        #endif
        loadedIdentifier = nil
    }

    func generate(request: LocalModelRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            #if canImport(LiteRTLM)
            guard let conversation else {
                continuation.finish(throwing: LocalModelError.runtimeUnavailable("No model is loaded."))
                return
            }
            let message = Message(request.prompt)
            let work = Task {
                do {
                    for try await chunk in conversation.sendMessageStream(message) {
                        if Task.isCancelled { break }
                        continuation.yield(chunk.toString)
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
            #else
            continuation.finish(throwing: LocalModelError.runtimeUnavailable("The LiteRT-LM package is not linked into this build."))
            #endif
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
