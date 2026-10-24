import SwiftUI
import UIKit
import Combine

// MARK: - Local AI Abstraction
protocol ResilixLocalAI {
    func respond(to query: String, knowledge: [FirstAidTopic]) async -> (text: String, source: String)
}

// Deterministic on-device engine — no network, no LLM download required for v1.
// Uses keyword matching + knowledge base ranking. Replace with Core ML / MLX LLM
// behind the same protocol later.
struct OfflineAIEngine: ResilixLocalAI {
    func respond(to query: String, knowledge: [FirstAidTopic]) async -> (text: String, source: String) {
        try? await Task.sleep(nanoseconds: 600_000_000)
        let q = query.lowercased()
        if q.contains("burn") { return (format(topic: knowledge.first(where: { $0.id == "burn" })!), "Local AI · Knowledge base") }
        if q.contains("bleed") { return (format(topic: knowledge.first(where: { $0.id == "bleeding" })!), "Local AI · Knowledge base") }
        if q.contains("cpr") || q.contains("heart") || q.contains("unresponsive") { return (format(topic: knowledge.first(where: { $0.id == "cpr" })!), "Local AI · Knowledge base") }
        if q.contains("chok") { return (format(topic: knowledge.first(where: { $0.id == "choking" })!), "Local AI · Knowledge base") }
        if q.contains("fracture") || q.contains("break") || q.contains("bone") { return (format(topic: knowledge.first(where: { $0.id == "fracture" })!), "Local AI · Knowledge base") }
        if q.contains("hypotherm") || q.contains("cold") || q.contains("freez") { return (format(topic: knowledge.first(where: { $0.id == "hypothermia" })!), "Local AI · Knowledge base") }
        let scored = knowledge.map { topic -> (FirstAidTopic, Int) in
            let text = (topic.title + " " + topic.category + " " + topic.steps.joined(separator: " ")).lowercased()
            let score = q.split(separator: " ").filter { text.contains($0) }.count
            return (topic, score)
        }.sorted { $0.1 > $1.1 }
        if let best = scored.first, best.1 > 0 {
            return (format(topic: best.0), "Knowledge base")
        }
        return (
            """
            **General emergency guidance (offline):**
            1. Ensure the area is safe for you and the injured person.
            2. Check responsiveness and breathing. Call for local help if anyone is nearby — Resilix mesh will relay if internet is down.
            3. Keep the person calm, warm, and still. Do not give food/drink if surgery may be needed.
            4. Describe what you see and I'll match it to the offline guides below.

            *Resilix Assist provides general information, not medical diagnosis. Seek professional help when available.*
            """,
            "Local AI · Generic"
        )
    }
    private func format(topic: FirstAidTopic) -> String {
        var s = "**\(topic.title)** — \(topic.category)\n\n"
        for (i, step) in topic.steps.enumerated() { s += "\(i+1). \(step)\n" }
        if let c = topic.caution { s += "\n⚠️ Caution: \(c)\n" }
        s += "\n*When to seek help:* \(topic.whenToSeekHelp)\n\n*This guidance is from the offline knowledge base.*"
        return s
    }
}

struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    var role: Role
    var text: String
    var timestamp = Date()
    var source: String?
    enum Role { case user, assistant }
}

// MARK: - AI Settings (in-memory; user can tweak per session)
struct AISettings: Equatable {
    enum ResponseLength: String, CaseIterable, Identifiable {
        case concise  = "Concise"
        case balanced = "Balanced"
        case detailed = "Detailed"
        var id: String { rawValue }
    }
    enum Tone: String, CaseIterable, Identifiable {
        case friendly    = "Friendly"
        case professional = "Professional"
        case empathetic  = "Empathetic"
        var id: String { rawValue }
    }
    enum Language: String, CaseIterable, Identifiable {
        case english = "English"
        case spanish = "Spanish"
        case french  = "French"
        case german  = "German"
        case auto    = "Auto-detect"
        var id: String { rawValue }
    }

    var creativity: Double = 0.0           // 0 = precise, 100 = creative
    var responseLength: ResponseLength = .balanced
    var tone: Tone = .friendly
    var language: Language = .auto
    var memoryEnabled: Bool = true
    var streamResponses: Bool = true
    var hapticsEnabled: Bool = true
    var localProcessing: Bool = true       // always true
    var conversationStorage: Bool = true   // always local
    var analyticsEnabled: Bool = false
    var voiceInputEnabled: Bool = true
}

// MARK: - View Model
@MainActor
final class AssistViewModel: ObservableObject {
    @Published var messages: [ChatMessage] = []
    @Published var input = ""
    @Published var isTyping = false
    @Published var hasUserSentMessage: Bool = false
    @Published var settings = AISettings()
    /// The local model service of the app (set by the view).
    var aiService: LocalAIService?
    private let knowledge = OfflineFirstAidStore.allTopics
    private let engine: ResilixLocalAI = OfflineAIEngine()

    init() {}

    func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        hasUserSentMessage = true
        input = ""
        isTyping = true
        Task {
            if let service = aiService,
               let model = service.activeModel,
               model.id != LocalAIService.knowledgeBaseModeID {
                await answerWithModel(service, prompt: trimmed)
            } else {
                // No language model selected: the bundled offline knowledge
                // base answers (this is a local retrieval, not a model).
                let result = await engine.respond(to: trimmed, knowledge: knowledge)
                isTyping = false
                messages.append(ChatMessage(role: .assistant, text: result.text, source: result.source))
            }
        }
    }

    /// Streams the answer of the selected on-device model.
    private func answerWithModel(_ service: LocalAIService, prompt: String) async {
        var answer = ""
        var index: Int?
        do {
            for try await piece in service.ask(prompt: prompt) {
                answer += piece
                if let index {
                    messages[index].text = answer
                } else {
                    messages.append(ChatMessage(role: .assistant,
                                               text: answer,
                                               source: service.activeModel?.displayName))
                    index = messages.count - 1
                }
            }
        } catch {
            let text = "The local model could not answer: \(error.localizedDescription)"
            if let index {
                messages[index].text = text
            } else {
                messages.append(ChatMessage(role: .assistant,
                                           text: text,
                                           source: service.activeModel?.displayName))
            }
        }
        isTyping = false
    }

    func sendQuickAction(_ action: QuickAction) {
        send(action.prompt)
    }

    func clear() {
        messages.removeAll()
        hasUserSentMessage = false
        isTyping = false
    }

    func newChat() { clear() }

    func regenerate() {
        guard let lastUser = messages.last(where: { $0.role == .user }) else { return }
        send(lastUser.text)
    }
}

// MARK: - Quick Action (used on the empty state)
struct QuickAction: Identifiable, Equatable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    let prompt: String

    static let all: [QuickAction] = [
        QuickAction(
            id: "firstaid",
            title: "First Aid",
            subtitle: "Treat injuries",
            icon: "cross.case.fill",
            color: Color(hex: "EF4444"),
            prompt: "How do I treat a severe bleeding injury?"
        ),
        QuickAction(
            id: "emergency",
            title: "Emergency Steps",
            subtitle: "What to do now",
            icon: "list.bullet.clipboard.fill",
            color: Color(hex: "F97316"),
            prompt: "Give me emergency steps for a burn."
        ),
        QuickAction(
            id: "shelter",
            title: "Nearby Shelters",
            subtitle: "Find help close by",
            icon: "mappin.and.ellipse",
            color: Color(hex: "22D3EE"),
            prompt: "Where is the nearest shelter and hospital?"
        ),
        QuickAction(
            id: "safety",
            title: "Safety Tips",
            subtitle: "Stay safe & calm",
            icon: "shield.lefthalf.filled",
            color: Color(hex: "22E36A"),
            prompt: "Safety guide for staying in place during an emergency."
        )
    ]
}

// MARK: - Assist liquid-glass tokens (very transparent — minimal white,
// blends into the page background)
private enum AssistGlass {
    static let fill   = Color.white.opacity(0.006)        // almost transparent
    static let border = Color.white.opacity(0.025)         // very faint hairline
    static let textOn = Color.white.opacity(0.78)          // softer white text
}

// MARK: - Root View
struct AssistView: View {
    @EnvironmentObject var app: ResilixAppModel
    @StateObject private var vm = AssistViewModel()
    @StateObject private var store = OfflineFirstAidService()
    @State private var showClearConfirm = false
    @State private var showSettings = false
    @State private var showModelManager = false
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                ResilixTheme.backgroundPrimary.ignoresSafeArea()

                VStack(spacing: 0) {
                    aiHeader
                        .padding(.horizontal, ResilixTheme.space16)
                        .padding(.top, ResilixTheme.space8)
                        .padding(.bottom, ResilixTheme.space12)

                    // Thin dark grey divider below the header
                    Rectangle()
                        .fill(ResilixTheme.separator)
                        .frame(height: 0.6)
                        .padding(.horizontal, ResilixTheme.space16)

                    // Empty state lives OUTSIDE the ScrollView so it can
                    // take the full remaining height and center its content
                    // vertically with Spacers.
                    if !vm.hasUserSentMessage {
                        emptyState
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: ResilixTheme.space16) {
                                    ForEach(vm.messages) { msg in
                                        AIMessageRow(message: msg)
                                            .id(msg.id)
                                    }
                                    if vm.isTyping {
                                        AIThinkingRow()
                                            .id("typing")
                                    }
                                }
                                .padding(.horizontal, ResilixTheme.space16)
                                .padding(.vertical, ResilixTheme.space8)
                            }
                            .onChange(of: vm.messages.count) { _, _ in
                                if let last = vm.messages.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                            }
                            .onChange(of: vm.isTyping) { _, _ in
                                withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                            }
                        }
                    }

                    Spacer(minLength: 0)

                    inputBar
                        .padding(.horizontal, ResilixTheme.space16)
                        .padding(.bottom, ResilixTheme.space12)
                        .padding(.top, ResilixTheme.space4)
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showSettings) {
                AISettingsSheet(settings: $vm.settings) {
                    vm.clear()
                }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationBackground(ResilixTheme.backgroundPrimary)
            }
            .sheet(isPresented: $showModelManager) {
                AIModelManagerView()
                    .environmentObject(app)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(ResilixTheme.backgroundPrimary)
            }
            .task {
                vm.aiService = app.aiService
                await app.aiService.refreshAvailability()
            }
            .alert("Clear conversation?", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) { vm.clear() }
            }
        }
    }

    // MARK: - Header (logo + title + pill + actions)
    private var aiHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            // Use the dark placeholder logo asset
            Image("ResilixLogoPlaceholderDark")
                .resizable()
                .scaledToFit()
                .frame(height: 36)
                .shadow(color: ResilixTheme.cyanGlowStrong, radius: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    // Bigger and less bold
                    Text("Offline AI")
                        .font(ResilixTheme.font(24, .bold))
                        .foregroundStyle(ResilixTheme.textPrimary)
                    Text("LOCAL")
                        .font(ResilixTheme.font(10, .heavy))
                        .tracking(0.6)
                        .foregroundStyle(ResilixTheme.successGreen)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            Capsule()
                                .fill(ResilixTheme.successGreen.opacity(0.12))
                                .overlay(
                                    Capsule()
                                        .stroke(ResilixTheme.successGreen.opacity(0.30), lineWidth: 0.6)
                                )
                        )
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(ResilixTheme.successGreen)
                        .frame(width: 6, height: 6)
                    Text(modelStatusLine)
                        .font(ResilixTheme.font(12, .medium))
                        .foregroundStyle(ResilixTheme.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            AIGlassCircleButton(systemImage: "cpu") { showModelManager = true }
                .accessibilityLabel("AI models")
            AIGlassCircleButton(systemImage: "gearshape") { showSettings = true }
                .accessibilityLabel("AI settings")
            AIGlassCircleButton(systemImage: "square.and.pencil") { vm.newChat() }
                .accessibilityLabel("New chat")
        }
    }

    /// Truthful description of the engine that answers the questions.
    private var modelStatusLine: String {
        guard let model = app.aiService.activeModel else {
            return "Offline knowledge base · No internet"
        }
        if model.id == LocalAIService.knowledgeBaseModeID {
            return "Offline knowledge base · No internet"
        }
        switch model.availability {
        case .ready:
            return "\(model.displayName) · On-device"
        case .notInstalled:
            return "\(model.displayName) · Not installed"
        case .runtimeUnavailable:
            return "\(model.displayName) · Runtime missing"
        case .unusable:
            return "\(model.displayName) · Unusable"
        }
    }

    // MARK: - Empty state (How can I help? + 4 quick actions, vertically centered)
    private var emptyState: some View {
        VStack(spacing: ResilixTheme.space20) {
            Spacer(minLength: 0)
            VStack(spacing: ResilixTheme.space10) {
                Text("How can I help?")
                    .font(ResilixTheme.font(30, .bold))
                    .foregroundStyle(Color.white)
                    .multilineTextAlignment(.center)
                Text("Your private AI assistant, running entirely on your device.")
                    .font(ResilixTheme.font(14, .regular))
                    .foregroundStyle(ResilixTheme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            // Running Locally pill (green, glowing)
            runningLocallyPill

            // 4 quick action cards (liquid glass, colored icons)
            quickActionsGrid
                .padding(.top, ResilixTheme.space4)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var runningLocallyPill: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(ResilixTheme.successGreen)
                .frame(width: 8, height: 8)
                .shadow(color: ResilixTheme.successGreen.opacity(0.9), radius: 6)
                .shadow(color: ResilixTheme.successGreen.opacity(0.5), radius: 10)
            Text("Running Locally")
                .font(ResilixTheme.font(13, .semibold))
                .tracking(0.4)
                .foregroundStyle(ResilixTheme.successGreen)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(ResilixTheme.successGreen.opacity(0.10))
                .overlay(
                    Capsule()
                        .stroke(ResilixTheme.successGreen.opacity(0.30), lineWidth: 0.6)
                )
        )
        .shadow(color: ResilixTheme.successGreen.opacity(0.25), radius: 10, y: 2)
    }

    private var quickActionsGrid: some View {
        let columns = [
            GridItem(.flexible(), spacing: 10),
            GridItem(.flexible(), spacing: 10)
        ]
        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(QuickAction.all) { action in
                QuickActionCard(action: action) {
                    vm.sendQuickAction(action)
                }
            }
        }
        .padding(.horizontal, ResilixTheme.space16)
    }

    // MARK: - Input bar (liquid glass, less white)
    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ZStack(alignment: .leading) {
                if vm.input.isEmpty {
                    Text("Ask Resilix anything…")
                        .font(ResilixTheme.font(15, .regular))
                        .foregroundStyle(Color.white.opacity(0.30))
                        .allowsHitTesting(false)
                }
                TextField("", text: $vm.input, axis: .vertical)
                    .lineLimit(1...4)
                    .font(ResilixTheme.font(15, .regular))
                    .foregroundStyle(Color.white)
                    .tint(Color.white)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit { vm.send(vm.input) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                    .fill(AssistGlass.fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                            .stroke(AssistGlass.border, lineWidth: 0.7)
                    )
            )
            .liquidGlassRounded(cornerRadius: ResilixTheme.cornerRadiusLarge, interactive: true)

            Button {
                // Mic placeholder
            } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(AssistGlass.fill)
                            .overlay(
                                Circle()
                                    .stroke(AssistGlass.border, lineWidth: 0.7)
                            )
                    )
                    .liquidGlassCircle(interactive: true)
            }
            .accessibilityLabel("Voice input")

            Button {
                vm.send(vm.input)
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(vm.input.trimmingCharacters(in: .whitespaces).isEmpty
                                     ? ResilixTheme.textTertiary
                                     : ResilixTheme.textOnAccent)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(vm.input.trimmingCharacters(in: .whitespaces).isEmpty
                                  ? AssistGlass.fill
                                  : ResilixTheme.brandCyan)
                            .overlay(
                                Circle()
                                    .stroke(AssistGlass.border, lineWidth: 0.7)
                            )
                    )
                    .liquidGlassCircle(interactive: true)
            }
            .disabled(vm.input.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send message")
        }
    }
}

// MARK: - Quick action card (used in empty state)
private struct QuickActionCard: View {
    let action: QuickAction
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(action.color.opacity(0.12))
                        .frame(width: 40, height: 40)
                    Image(systemName: action.icon)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(action.color)
                }
                VStack(alignment: .center, spacing: 2) {
                    Text(action.title)
                        .font(ResilixTheme.font(14, .bold))
                        .foregroundStyle(ResilixTheme.textPrimary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                    Text(action.subtitle)
                        .font(ResilixTheme.font(11, .regular))
                        .foregroundStyle(ResilixTheme.textSecondary)
                        .lineLimit(1)
                        .multilineTextAlignment(.center)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                    .fill(AssistGlass.fill)
                    .overlay(
                        RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                            .stroke(AssistGlass.border, lineWidth: 0.7)
                    )
            )
            .liquidGlassRounded(cornerRadius: ResilixTheme.cornerRadiusLarge, interactive: true)
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - Liquid glass circle button (used in header)
struct AIGlassCircleButton: View {
    let systemImage: String
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(ResilixTheme.textPrimary)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(AssistGlass.fill)
                        .overlay(
                            Circle()
                                .stroke(AssistGlass.border, lineWidth: 0.7)
                        )
                )
                .liquidGlassCircle(interactive: true)
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - AI message row (no bubble for assistant; user is a liquid-glass bubble)
struct AIMessageRow: View {
    let message: ChatMessage

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 60) }
            VStack(alignment: isUser ? .trailing : .leading, spacing: 6) {
                if isUser {
                    // User messages — liquid glass box
                    Text(message.text)
                        .font(ResilixTheme.font(15, .regular))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                                .fill(AssistGlass.fill)
                                .overlay(
                                    RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                                        .stroke(AssistGlass.border, lineWidth: 0.7)
                                )
                        )
                        .liquidGlassRounded(cornerRadius: ResilixTheme.cornerRadiusLarge, interactive: false)
                } else {
                    // AI messages — no bubble
                    Text(.init(message.text))
                        .font(ResilixTheme.font(15, .regular))
                        .foregroundStyle(ResilixTheme.textPrimary)
                        .textSelection(.enabled)
                }
                HStack(spacing: 6) {
                    Text(message.timestamp, style: .time)
                        .font(ResilixTheme.font(10, .medium))
                        .foregroundStyle(ResilixTheme.textTertiary)
                    if let src = message.source, !isUser {
                        Text("· \(src)")
                            .font(ResilixTheme.font(10, .medium))
                            .foregroundStyle(ResilixTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
            if !isUser { Spacer(minLength: 60) }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - AI thinking row
struct AIThinkingRow: View {
    @State private var phase: CGFloat = 0
    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(ResilixTheme.brandCyan)
                        .frame(width: 6, height: 6)
                        .opacity(phase == CGFloat(i) ? 1 : 0.3)
                }
            }
            Text("Resilix is thinking locally…")
                .font(ResilixTheme.font(12, .medium))
                .foregroundStyle(ResilixTheme.textSecondary)
            Spacer()
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: false)) {
                phase = 2
            }
        }
    }
}

// MARK: - AI Settings Sheet (expanded, more features, more organized)
struct AISettingsSheet: View {
    @Binding var settings: AISettings
    let onClear: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showClearConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {

                    // ===== AI BEHAVIOR =====
                    sectionHeader("AI BEHAVIOR")
                    settingsCard {
                        VStack(alignment: .leading, spacing: 14) {
                            SettingSliderRow(
                                icon: "slider.horizontal.3",
                                iconColor: ResilixTheme.brandCyan,
                                title: "Creativity",
                                valueText: "\(Int(settings.creativity))%",
                                valueColor: ResilixTheme.brandCyan
                            ) {
                                HStack(spacing: 8) {
                                    Text("Precise")
                                        .font(ResilixTheme.font(10, .medium))
                                        .foregroundStyle(ResilixTheme.textTertiary)
                                    Slider(value: $settings.creativity, in: 0...100, step: 1)
                                        .tint(ResilixTheme.brandCyan)
                                    Text("Creative")
                                        .font(ResilixTheme.font(10, .medium))
                                        .foregroundStyle(ResilixTheme.textTertiary)
                                }
                            }

                            divider

                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    SettingIconBadge(icon: "ruler", color: ResilixTheme.brandCyan)
                                    Text("Response Length")
                                        .font(ResilixTheme.font(15, .semibold))
                                        .foregroundStyle(ResilixTheme.textPrimary)
                                    Spacer()
                                }
                                HStack(spacing: 8) {
                                    ForEach(AISettings.ResponseLength.allCases) { len in
                                        Button {
                                            settings.responseLength = len
                                        } label: {
                                            Text(len.rawValue)
                                                .font(ResilixTheme.font(13, .semibold))
                                                .foregroundStyle(settings.responseLength == len ? .white : ResilixTheme.textPrimary)
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 36)
                                                .background(
                                                    Capsule()
                                                        .fill(settings.responseLength == len
                                                              ? ResilixTheme.brandCyan
                                                              : AssistGlass.fill)
                                                )
                                                .overlay(
                                                    Capsule()
                                                        .stroke(AssistGlass.border, lineWidth: 0.6)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            divider

                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    SettingIconBadge(icon: "person.wave.2", color: ResilixTheme.brandCyan)
                                    Text("Tone")
                                        .font(ResilixTheme.font(15, .semibold))
                                        .foregroundStyle(ResilixTheme.textPrimary)
                                    Spacer()
                                }
                                HStack(spacing: 8) {
                                    ForEach(AISettings.Tone.allCases) { t in
                                        Button {
                                            settings.tone = t
                                        } label: {
                                            Text(t.rawValue)
                                                .font(ResilixTheme.font(12, .semibold))
                                                .foregroundStyle(settings.tone == t ? .white : ResilixTheme.textPrimary)
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 34)
                                                .background(
                                                    Capsule()
                                                        .fill(settings.tone == t
                                                              ? ResilixTheme.brandCyan
                                                              : AssistGlass.fill)
                                                )
                                                .overlay(
                                                    Capsule()
                                                        .stroke(AssistGlass.border, lineWidth: 0.6)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }

                            divider

                            SettingPickerRow(
                                icon: "globe",
                                iconColor: ResilixTheme.brandCyan,
                                title: "Language",
                                selection: $settings.language
                            )
                        }
                    }

                    // ===== AI FEATURES =====
                    sectionHeader("AI FEATURES")
                    settingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            SettingToggleRow(
                                icon: "brain",
                                iconColor: ResilixTheme.brandCyan,
                                title: "Memory",
                                subtitle: "Remember context across sessions",
                                isOn: $settings.memoryEnabled,
                                tint: ResilixTheme.successGreen
                            )
                            divider
                            SettingToggleRow(
                                icon: "waveform",
                                iconColor: ResilixTheme.brandCyan,
                                title: "Stream Responses",
                                subtitle: "Show answers word-by-word",
                                isOn: $settings.streamResponses,
                                tint: ResilixTheme.successGreen
                            )
                            divider
                            SettingToggleRow(
                                icon: "mic",
                                iconColor: ResilixTheme.brandCyan,
                                title: "Voice Input",
                                subtitle: "Allow microphone prompts",
                                isOn: $settings.voiceInputEnabled,
                                tint: ResilixTheme.successGreen
                            )
                            divider
                            SettingToggleRow(
                                icon: "iphone.haptic",
                                iconColor: ResilixTheme.brandCyan,
                                title: "Haptics",
                                subtitle: "Subtle vibration on responses",
                                isOn: $settings.hapticsEnabled,
                                tint: ResilixTheme.successGreen
                            )
                        }
                    }

                    // ===== PRIVACY =====
                    sectionHeader("PRIVACY")
                    settingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            SettingStaticRow(
                                icon: "lock.shield",
                                iconColor: ResilixTheme.successGreen,
                                title: "Local Processing",
                                subtitle: "All AI runs on this device"
                            )
                            divider
                            SettingStaticRow(
                                icon: "internaldrive",
                                iconColor: ResilixTheme.brandCyan,
                                title: "Conversation Storage",
                                subtitle: "Saved locally, never uploaded"
                            )
                            divider
                            SettingToggleRow(
                                icon: "chart.bar",
                                iconColor: ResilixTheme.brandCyan,
                                title: "Anonymous Analytics",
                                subtitle: "Help improve offline AI quality",
                                isOn: $settings.analyticsEnabled,
                                tint: ResilixTheme.successGreen
                            )
                            divider
                            Button {
                                showClearConfirm = true
                            } label: {
                                HStack(spacing: 12) {
                                    SettingIconBadge(icon: "trash", color: ResilixTheme.emergencyRed)
                                    Text("Clear All Conversations")
                                        .font(ResilixTheme.font(15, .bold))
                                        .foregroundStyle(ResilixTheme.emergencyRed)
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    // ===== ABOUT =====
                    sectionHeader("ABOUT")
                    settingsCard {
                        VStack(alignment: .leading, spacing: 0) {
                            SettingStaticRow(
                                icon: "info.circle",
                                iconColor: ResilixTheme.brandCyan,
                                title: "Engine",
                                subtitle: "Offline keyword + knowledge base"
                            )
                            divider
                            SettingStaticRow(
                                icon: "tag",
                                iconColor: ResilixTheme.brandCyan,
                                title: "Version",
                                subtitle: "Resilix Assist 1.0"
                            )
                        }
                    }

                    Spacer(minLength: ResilixTheme.space24)
                }
            }
            .background(ResilixTheme.backgroundPrimary)
            .navigationTitle("AI Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(ResilixTheme.brandCyan)
                }
            }
            .alert("Clear all conversations?", isPresented: $showClearConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Clear", role: .destructive) {
                    onClear()
                    dismiss()
                }
            }
        }
    }

    // MARK: - helpers
    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.06))
            .frame(height: 0.6)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(ResilixTheme.font(11, .heavy))
            .tracking(1.0)
            .foregroundStyle(ResilixTheme.textTertiary)
            .padding(.horizontal, ResilixTheme.space20)
            .padding(.top, 6)
    }

    private func settingsCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            content()
                .padding(16)
        }
        .background(
            RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                .fill(AssistGlass.fill)
                .overlay(
                    RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                        .stroke(AssistGlass.border, lineWidth: 0.6)
                )
        )
        .liquidGlassRounded(cornerRadius: ResilixTheme.cornerRadiusLarge, interactive: false)
        .padding(.horizontal, ResilixTheme.space16)
    }
}

// MARK: - Settings row primitives

private struct SettingIconBadge: View {
    let icon: String
    let color: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(color.opacity(0.18))
                .frame(width: 32, height: 32)
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(color)
        }
    }
}

private struct SettingSliderRow<Content: View>: View {
    let icon: String
    let iconColor: Color
    let title: String
    let valueText: String?
    let valueColor: Color?
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingIconBadge(icon: icon, color: iconColor)
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(ResilixTheme.font(15, .semibold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                content()
            }
            if let v = valueText {
                Spacer()
                Text(v)
                    .font(ResilixTheme.font(13, .heavy))
                    .foregroundStyle(valueColor ?? ResilixTheme.textPrimary)
            }
        }
    }
}

private struct SettingToggleRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let tint: Color

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingIconBadge(icon: icon, color: iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ResilixTheme.font(15, .semibold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                Text(subtitle)
                    .font(ResilixTheme.font(11, .regular))
                    .foregroundStyle(ResilixTheme.textTertiary)
            }
            Spacer()
            Toggle("", isOn: $isOn.animation(.easeInOut(duration: 0.18)))
                .labelsHidden()
                .tint(tint)
        }
        .padding(.vertical, 6)
    }
}

private struct SettingStaticRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingIconBadge(icon: icon, color: iconColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ResilixTheme.font(15, .semibold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                Text(subtitle)
                    .font(ResilixTheme.font(11, .regular))
                    .foregroundStyle(ResilixTheme.textTertiary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}

private struct SettingPickerRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    @Binding var selection: AISettings.Language

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            SettingIconBadge(icon: icon, color: iconColor)
            Text(title)
                .font(ResilixTheme.font(15, .semibold))
                .foregroundStyle(ResilixTheme.textPrimary)
            Spacer()
            Menu {
                ForEach(AISettings.Language.allCases) { lang in
                    Button(lang.rawValue) { selection = lang }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(selection.rawValue)
                        .font(ResilixTheme.font(13, .semibold))
                        .foregroundStyle(ResilixTheme.brandCyan)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(ResilixTheme.textTertiary)
                }
            }
        }
        .padding(.vertical, 6)
    }
}

#Preview { AssistView() }
