import Foundation
import Combine

/// Runs the on-device AI of the app.
///
/// Three engines are offered, all of them running completely offline:
///
/// * **Gemma 4 E2B** (`google/gemma-4-E2B`, Apache-2.0) through the
///   LiteRT-LM runtime,
/// * **Qwen3 0.6B** (`Qwen/Qwen3-0.6B`, Apache-2.0) through the same
///   runtime,
/// * **Apple Foundation Models** (AFM 3) through the system framework.
///
/// In addition the curated offline first-aid knowledge base of the app can
/// answer questions without any model at all.
///
/// The service never falls back to a cloud service: when a runtime or a
/// model file is missing the user gets the exact reason.
@MainActor
final class LocalAIService: ObservableObject {
    /// Identifier of the offline knowledge base mode.
    static let knowledgeBaseModeID = "resilix.firstaid.knowledge"

    @Published private(set) var models: [LocalModelDescriptor] = []
    @Published private(set) var activeModelID: String?
    @Published private(set) var conversation: [AIChatTurn] = []
    @Published private(set) var isGenerating = false
    @Published private(set) var statusMessage: String = ""
    @Published private(set) var lastErrorMessage: String?

    private let persistence = PersistenceController.shared
    private let appleRuntime = AppleFoundationModelRuntime()
    private let liteRTRuntime = LiteRTModelRuntime()
    private var activeRuntime: LocalModelRuntime?

    init() {
        models = Self.catalogue()
    }

    // MARK: - Catalogue

    /// The exact model identifiers. Nothing is substituted silently.
    nonisolated static func catalogue() -> [LocalModelDescriptor] {
        [
            LocalModelDescriptor(id: "gemma-4-e2b",
                                 family: .gemma,
                                 displayName: "Gemma 4 E2B",
                                 modelID: "google/gemma-4-E2B",
                                 artifactID: "litert-community/gemma-4-E2B-it-litert-lm",
                                 fileName: "gemma-4-e2b-it.litertlm",
                                 approximateBytes: 2_580_000_000,
                                 license: "Apache-2.0",
                                 runtimeRequirement: "LiteRT-LM (iOS 17+), ~2.6 GB",
                                 localRelativePath: nil,
                                 isDownloaded: false,
                                 availability: .runtimeUnavailable,
                                 notes: L("Multimodal, 128K context, text and image input.")),
            LocalModelDescriptor(id: "qwen3-0.6b",
                                 family: .qwen,
                                 displayName: "Qwen3 0.6B",
                                 modelID: "Qwen/Qwen3-0.6B",
                                 artifactID: "litert-community/Qwen3-0.6B",
                                 fileName: "qwen3-0.6b.litertlm",
                                 approximateBytes: 0,
                                 license: "Apache-2.0",
                                 runtimeRequirement: "LiteRT-LM (iOS 17+)",
                                 localRelativePath: nil,
                                 isDownloaded: false,
                                 availability: .runtimeUnavailable,
                                 notes: L("Smallest Qwen3 release. Qwen3.5 starts at 0.8B, there is no Qwen3.5 0.6B.")),
            LocalModelDescriptor(id: "apple-foundation-models",
                                 family: .apple,
                                 displayName: L("Apple Foundation Models (AFM 3)"),
                                 modelID: "apple/system-language-model",
                                 artifactID: nil,
                                 fileName: "",
                                 approximateBytes: 0,
                                 license: L("Apple system model"),
                                 runtimeRequirement: L("iOS 26+ with Apple Intelligence enabled"),
                                 localRelativePath: nil,
                                 isDownloaded: true,
                                 availability: .runtimeUnavailable,
                                 notes: L("Provided by the system, nothing has to be downloaded."))
        ]
    }

    /// The offline knowledge base mode.
    static var knowledgeBaseDescriptor: LocalModelDescriptor {
        LocalModelDescriptor(id: knowledgeBaseModeID,
                             family: .apple,
                             displayName: L("First-aid knowledge base (on device)"),
                             modelID: "resilix/offline-first-aid",
                             artifactID: nil,
                             fileName: "",
                             approximateBytes: 0,
                             license: L("Bundled with the app"),
                             runtimeRequirement: L("Always available, no model needed"),
                             localRelativePath: nil,
                             isDownloaded: true,
                             availability: .ready,
                             notes: L("Curated offline content, not a language model."))
    }

    var knowledgeBase: LocalModelDescriptor { Self.knowledgeBaseDescriptor }

    /// All selectable modes (models plus the knowledge base).
    var selectableModes: [LocalModelDescriptor] { models + [knowledgeBase] }

    var activeModel: LocalModelDescriptor? {
        selectableModes.first { $0.id == activeModelID }
    }

    // MARK: - Lifecycle

    func load() async {
        conversation = await persistence.loadAIConversation()
        await refreshAvailability()
    }

    /// Recalculates the availability of every mode.
    func refreshAvailability() async {
        var updated = models
        for index in updated.indices {
            switch updated[index].family {
            case .apple:
                updated[index].availability = appleRuntime.isAvailable ? .ready : .runtimeUnavailable
            case .gemma, .qwen:
                guard liteRTRuntime.isAvailable else {
                    updated[index].availability = .runtimeUnavailable
                    continue
                }
                if let path = updated[index].localRelativePath,
                   await persistence.fileExists(at: path) {
                    updated[index].isDownloaded = true
                    updated[index].availability = .ready
                } else {
                    updated[index].isDownloaded = false
                    updated[index].availability = .notInstalled
                }
            }
        }
        models = updated
    }

    /// Runtime that would be used for a mode.
    private func runtime(for model: LocalModelDescriptor) -> LocalModelRuntime {
        switch model.family {
        case .apple: return appleRuntime
        case .gemma, .qwen: return liteRTRuntime
        }
    }

    /// Reason why a mode cannot be used right now.
    func unavailableReason(for model: LocalModelDescriptor) -> String? {
        switch model.family {
        case .apple:
            return appleRuntime.unavailableReason
        case .gemma, .qwen:
            return liteRTRuntime.unavailableReason
        }
    }

    /// Selects a mode and loads the model (only one model stays in memory).
    func select(modelID: String) async {
        guard let model = selectableModes.first(where: { $0.id == modelID }) else { return }
        // Free the memory of the previous model before the new one is loaded.
        activeRuntime?.unload()
        activeRuntime = nil
        activeModelID = modelID

        if model.id == Self.knowledgeBaseModeID {
            statusMessage = L("Offline knowledge base selected.")
            return
        }

        let runtime = runtime(for: model)
        guard runtime.isAvailable else {
            statusMessage = runtime.unavailableReason ?? L("The runtime is not available.")
            lastErrorMessage = statusMessage
            return
        }
        let url = model.localRelativePath.map { persistence.baseURL.appendingPathComponent($0) }
        do {
            try await runtime.load(model: model, modelURL: url)
            activeRuntime = runtime
            statusMessage = "\(model.displayName) is loaded."
            lastErrorMessage = nil
        } catch {
            statusMessage = error.localizedDescription
            lastErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Model files

    /// Imports a `.litertlm` file that the user selected (e.g. from Files).
    func importModel(from url: URL, for modelID: String) async throws {
        guard let index = models.firstIndex(where: { $0.id == modelID }) else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let fileName = models[index].fileName.isEmpty ? url.lastPathComponent : models[index].fileName
        let relative = "\(ResilixConstants.modelDirectoryName)/\(fileName)"
        try await persistence.write(data, to: relative)
        models[index].localRelativePath = relative
        models[index].isDownloaded = true
        await refreshAvailability()
    }

    func deleteModel(modelID: String) async {
        guard let index = models.firstIndex(where: { $0.id == modelID }) else { return }
        if let relative = models[index].localRelativePath {
            await persistence.removeFile(at: relative)
        }
        models[index].localRelativePath = nil
        models[index].isDownloaded = false
        if activeModelID == modelID {
            activeRuntime?.unload()
            activeRuntime = nil
        }
        await refreshAvailability()
    }

    // MARK: - Asking

    /// Sends a prompt to the selected engine and streams the answer.
    ///
    /// The returned stream yields the answer piece by piece. Errors are
    /// forwarded to the consumer, so the UI can show the real reason when
    /// a model is missing.
    func ask(prompt: String) -> AsyncThrowingStream<String, Error> {
        guard let model = activeModel else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LocalModelError.noModelSelected)
            }
        }

        if model.id == Self.knowledgeBaseModeID {
            return AsyncThrowingStream { continuation in
                continuation.yield(knowledgeBaseAnswer(for: prompt))
                continuation.finish()
            }
        }

        guard let runtime = activeRuntime, runtime.isLoaded else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: LocalModelError.runtimeUnavailable(
                    unavailableReason(for: model) ?? L("No model is loaded.")))
            }
        }

        let request = LocalModelRequest(prompt: prompt,
                                        systemInstructions: L("You are the on-device assistant of the Resilix offline mesh app."),
                                        maxTokens: 512)
        return runtime.generate(request: request)
    }

    /// Runs a prompt and appends the exchange to the persisted conversation.
    func askAndStore(prompt: String) async {
        isGenerating = true
        lastErrorMessage = nil
        conversation.append(AIChatTurn(role: .user, text: prompt))
        await persistConversation()

        var answer = ""
        do {
            for try await piece in ask(prompt: prompt) {
                answer += piece
            }
            conversation.append(AIChatTurn(role: .assistant,
                                           text: answer,
                                           source: activeModel?.modelID))
        } catch {
            lastErrorMessage = error.localizedDescription
            if answer.isEmpty {
                conversation.append(AIChatTurn(role: .assistant,
                                               text: "",
                                               source: activeModel?.modelID))
            }
        }
        isGenerating = false
        await persistConversation()
    }

    func cancel() {
        activeRuntime?.cancel()
        isGenerating = false
    }

    func clearConversation() async {
        conversation.removeAll()
        await persistConversation()
    }

    private func persistConversation() async {
        try? await persistence.saveAIConversation(conversation)
    }

    // MARK: - Offline knowledge base

    /// Answers from the curated first-aid content that ships with the app.
    func knowledgeBaseAnswer(for question: String) -> String {
        let query = question.lowercased()
        let topics = OfflineFirstAidStore.allTopics
        let scored = topics.map { topic -> (FirstAidTopic, Int) in
            var score = 0
            if query.contains(topic.title.lowercased()) { score += 10 }
            if query.contains(topic.category.lowercased()) { score += 6 }
            for step in topic.steps where query.contains(step.lowercased().prefix(12)) { score += 2 }
            for word in query.split(separator: " ") where topic.title.lowercased().contains(word) { score += 1 }
            return (topic, score)
        }
        let best = scored.max { $0.1 < $1.1 }
        guard let best, best.1 > 0 else {
            return String(format: L("No offline entry matches “%@”."), question)
                + " "
                + L("The bundled first-aid topics cover:")
                + " "
                + topics.map { $0.title }.joined(separator: ", ")
                + "."
        }
        let topic = best.0
        var answer = "\(topic.title)\n\n"
        answer += topic.steps.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        if let caution = topic.caution { answer += "\n\n" + L("Caution:") + " \(caution)" }
        answer += "\n\n\(topic.whenToSeekHelp)"
        return answer
    }
}
