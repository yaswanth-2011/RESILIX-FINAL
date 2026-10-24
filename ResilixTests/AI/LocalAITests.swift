import XCTest
@testable import Resilix

@MainActor
final class LocalAITests: XCTestCase {
    func testCatalogueUsesTheVerifiedModelIdentifiers() {
        let models = LocalAIService.catalogue()
        XCTAssertTrue(models.contains { $0.modelID == "google/gemma-4-E2B" })
        XCTAssertTrue(models.contains { $0.modelID == "Qwen/Qwen3-0.6B" })
        XCTAssertTrue(models.contains { $0.family == .apple })
    }

    func testNoSilentSubstitution() {
        for model in LocalAIService.catalogue() {
            let identifier = model.modelID.lowercased()
            XCTAssertFalse(identifier.contains("qwen3.5-0.6b"),
                           "Qwen3.5 has no 0.6B release — the model must not be renamed")
            XCTAssertFalse(identifier.contains("gemma-3"))
        }
    }

    func testLicencesAreStated() {
        for model in LocalAIService.catalogue() {
            XCTAssertFalse(model.license.isEmpty)
            XCTAssertFalse(model.runtimeRequirement.isEmpty)
        }
    }

    func testAvailabilityIsTruthful() async {
        let service = LocalAIService()
        await service.refreshAvailability()
        for model in service.models where model.family != .apple {
            if model.availability == .runtimeUnavailable {
                XCTAssertNotNil(service.unavailableReason(for: model))
            }
        }
    }

    func testKnowledgeBaseAnswersWithoutAModel() {
        let service = LocalAIService()
        let answer = service.knowledgeBaseAnswer(for: "How do I treat a burn?")
        XCTAssertTrue(answer.contains("Burn"))
    }

    func testKnowledgeBaseReportsUnknownQuestion() {
        let service = LocalAIService()
        let answer = service.knowledgeBaseAnswer(for: "How do I calibrate a particle accelerator?")
        XCTAssertTrue(answer.contains("No offline entry"))
    }

    func testAskingWithoutAModelFails() async {
        let service = LocalAIService()
        do {
            for try await _ in service.ask(prompt: "hello") {}
            XCTFail("Without a model the request must fail instead of inventing an answer")
        } catch {
            XCTAssertTrue(error is LocalModelError)
        }
    }

    func testConversationIsPersisted() async {
        let service = LocalAIService()
        await service.clearConversation()
        await service.askAndStore(prompt: "How do I stop severe bleeding?")
        let stored = await PersistenceController.shared.loadAIConversation()
        XCTAssertFalse(stored.isEmpty)
        XCTAssertEqual(stored.first?.role, .user)
        await service.clearConversation()
    }
}
