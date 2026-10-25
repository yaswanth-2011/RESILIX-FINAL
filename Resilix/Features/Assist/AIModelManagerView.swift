import SwiftUI
import UniformTypeIdentifiers

/// Management of the local AI models.
///
/// The sheet shows the exact model identifiers, the licence, the runtime
/// requirement and the real state of every option. A model that is not
/// installed or whose runtime is missing is labelled with the reason — the
/// app never pretends that a model is available.
struct AIModelManagerView: View {
    @EnvironmentObject var app: ResilixAppModel
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var importTargetID: String?
    @State private var message: String?

    private var service: LocalAIService { app.aiService }

    var body: some View {
        NavigationStack {
            ZStack {
                ResilixTheme.backgroundPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: ResilixTheme.space16) {
                        Text(L("On-device models"))
                            .font(ResilixTheme.font(22, .bold))
                            .foregroundStyle(ResilixTheme.textPrimary)

                        Text(L("Every model runs completely on this device. No answer ever leaves the phone."))
                            .font(ResilixTheme.font(13, .regular))
                            .foregroundStyle(ResilixTheme.textSecondary)

                        // How-to-install guidance so the bundled models are
                        // visible and actionable instead of hidden.
                        installGuideCard

                        ForEach(service.selectableModes) { model in
                            modelCard(model)
                        }
                    }
                    .padding(.horizontal, ResilixTheme.space20)
                    .padding(.vertical, ResilixTheme.space16)
                }
            }
            .navigationTitle("AI Models")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                        .font(ResilixTheme.font(15, .semibold))
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.data],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first, let target = importTargetID {
                        Task { await importModel(url, target: target) }
                    }
                case .failure:
                    message = L("The model file could not be opened.")
                }
            }
            .alert(L("AI Models"), isPresented: .constant(message != nil), presenting: message) { _ in
                Button(L("OK")) { message = nil }
            } message: { text in
                Text(text)
            }
        }
    }

    // MARK: - Card

    private func modelCard(_ model: LocalModelDescriptor) -> some View {
        VStack(alignment: .leading, spacing: ResilixTheme.space8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.displayName)
                        .font(ResilixTheme.font(16, .semibold))
                        .foregroundStyle(ResilixTheme.textPrimary)
                    Text(model.modelID)
                        .font(ResilixTheme.font(11, .regular))
                        .foregroundStyle(ResilixTheme.textTertiary)
                }
                Spacer()
                stateBadge(for: model)
            }

            if let artifact = model.artifactID {
                Text(L("assist.artifact") + ": \(artifact)")
                    .font(ResilixTheme.font(11, .regular))
                    .foregroundStyle(ResilixTheme.textTertiary)
            }

            Text(model.runtimeRequirement)
                .font(ResilixTheme.font(12, .regular))
                .foregroundStyle(ResilixTheme.textSecondary)

            Text(model.notes)
                .font(ResilixTheme.font(12, .regular))
                .foregroundStyle(ResilixTheme.textSecondary)

            if model.approximateBytes > 0 {
                Text(L("assist.download.size") + " \(model.formattedSize)")
                    .font(ResilixTheme.font(11, .regular))
                    .foregroundStyle(ResilixTheme.textTertiary)
            }

            Text(L("assist.licence") + ": \(model.license)")
                .font(ResilixTheme.font(11, .regular))
                .foregroundStyle(ResilixTheme.textTertiary)

            if let reason = service.unavailableReason(for: model), model.id != LocalAIService.knowledgeBaseModeID {
                Text(reason)
                    .font(ResilixTheme.font(11, .regular))
                    .foregroundStyle(ResilixTheme.brandAmber)
            }

            HStack(spacing: ResilixTheme.space12) {
                Button {
                    Task { await service.select(modelID: model.id) }
                } label: {
                    Text(service.activeModelID == model.id ? L("Selected") : L("Use"))
                        .font(ResilixTheme.font(14, .semibold))
                        .foregroundStyle(service.activeModelID == model.id ? ResilixTheme.textSecondary : .white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(service.activeModelID == model.id
                                    ? ResilixTheme.surfacePrimary
                                    : ResilixTheme.brandCyan)
                        .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusMedium, style: .continuous))
                }
                .buttonStyle(.plain)

                if model.family != .apple {
                    Button {
                        importTargetID = model.id
                        showImporter = true
                    } label: {
                        Text(model.isDownloaded ? L("Replace file") : L("Install file"))
                            .font(ResilixTheme.font(14, .semibold))
                            .foregroundStyle(ResilixTheme.textPrimary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(ResilixTheme.surfacePrimary)
                            .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusMedium, style: .continuous))
                    }
                    .buttonStyle(.plain)

                    if model.isDownloaded {
                        Button {
                            Task { await service.deleteModel(modelID: model.id) }
                        } label: {
                            Text(L("Remove"))
                                .font(ResilixTheme.font(14, .semibold))
                                .foregroundStyle(ResilixTheme.emergencyRed)
                        }
                        .buttonStyle(.plain)
                    }
                }
                Spacer()
            }
        }
        .padding(ResilixTheme.space16)
        .background(ResilixTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                .stroke(ResilixTheme.separator.opacity(0.6), lineWidth: 0.6)
        )
    }

    // MARK: - Install guide

    /// Shows where to get Gemma/Qwen model files and how to enable them.
    private var installGuideCard: some View {
        VStack(alignment: .leading, spacing: ResilixTheme.space10) {
            Text(L("assist.install.title"))
                .font(ResilixTheme.font(16, .semibold))
                .foregroundStyle(ResilixTheme.textPrimary)

            VStack(alignment: .leading, spacing: ResilixTheme.space4) {
                installGuideRow(
                    icon: "arrow.down.circle",
                    title: L("assist.install.gemma.title"),
                    subtitle: L("assist.install.gemma.sub"),
                    url: L("assist.install.gemma.url")
                )
                Divider().background(ResilixTheme.separator)
                installGuideRow(
                    icon: "arrow.down.circle",
                    title: L("assist.install.qwen.title"),
                    subtitle: L("assist.install.qwen.sub"),
                    url: L("assist.install.qwen.url")
                )
                Divider().background(ResilixTheme.separator)
                installGuideRow(
                    icon: "chip.fill",
                    title: L("assist.install.runtime.title"),
                    subtitle: L("assist.install.runtime.sub"),
                    url: L("assist.install.runtime.url")
                )
            }

            Text(L("assist.install.note"))
                .font(ResilixTheme.font(11, .regular))
                .foregroundStyle(ResilixTheme.textTertiary)
        }
        .padding(ResilixTheme.space16)
        .background(ResilixTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                .stroke(ResilixTheme.separator.opacity(0.6), lineWidth: 0.6)
        )
    }

    private func installGuideRow(icon: String, title: String, subtitle: String, url: String) -> some View {
        HStack(spacing: ResilixTheme.space10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ResilixTheme.brandCyan)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ResilixTheme.font(13, .semibold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                Text(subtitle)
                    .font(ResilixTheme.font(11, .regular))
                    .foregroundStyle(ResilixTheme.textSecondary)
            }
            Spacer()
            Link(destination: URL(string: url)!) {
                HStack(spacing: 4) {
                    Text(L("assist.install.get")).font(ResilixTheme.font(11, .semibold))
                    Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                }
                .foregroundStyle(ResilixTheme.brandCyan)
            }
        }
        .padding(.vertical, 2)
    }

    private func stateBadge(for model: LocalModelDescriptor) -> some View {
        let text: String
        let color: Color
        switch model.availability {
        case .ready:
            text = "Ready"
            color = ResilixTheme.successGreen
        case .notInstalled:
            text = L("Not installed")
            color = ResilixTheme.brandAmber
        case .runtimeUnavailable:
            text = L("No runtime")
            color = ResilixTheme.brandAmber
        case .unusable:
            text = "Unusable"
            color = ResilixTheme.emergencyRed
        }
        return ResilixStatusBadge(text: text, color: color)
    }

    private func importModel(_ url: URL, target: String) async {
        do {
            try await service.importModel(from: url, for: target)
            await service.select(modelID: target)
            message = L("The model file was installed.")
        } catch {
            message = error.localizedDescription
        }
    }
}
