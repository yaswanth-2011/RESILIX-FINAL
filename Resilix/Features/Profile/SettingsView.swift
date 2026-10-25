import SwiftUI

// MARK: - Full-screen Settings
// Native iOS-style grouped settings: ACCOUNT / NETWORK / APP sections in
// rounded containers with subtle separators, icons, chevrons and toggles.

struct SettingsView: View {
    @EnvironmentObject var app: ResilixAppModel
    @Environment(\.dismiss) var dismiss

    @AppStorage("appearance") private var appearance: String = Appearance.dark.rawValue
    @AppStorage("language") private var language: Language = .english
    @AppStorage("autoRelay") private var autoRelay = false
    @AppStorage("showDebugInfo") private var showDebugInfo = false

    @State private var showLanguagePicker = false
    @State private var showAppearance = false

    enum Appearance: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
        var id: String { rawValue }

        /// Localized name shown in the appearance dialog.
        var label: String {
            switch self {
            case .system: return L("settings.system")
            case .light:  return L("settings.light")
            case .dark:   return L("settings.dark")
            }
        }
    }

    enum Language: String, CaseIterable, Identifiable {
        case english = "English"
        case hindi = "Hindi"
        case telugu = "Telugu"
        case tamil = "Tamil"
        case kannada = "Kannada"
        case malayalam = "Malayalam"
        case marathi = "Marathi"
        case bengali = "Bengali"
        case gujarati = "Gujarati"
        case punjabi = "Punjabi"
        case urdu = "Urdu"
        var id: String { rawValue }

        /// Native name of the language, shown in the language picker.
        var label: String {
            switch self {
            case .english:  return L("language.english")
            case .hindi:    return L("language.hindi")
            case .telugu:   return L("language.telugu")
            case .tamil:    return L("language.tamil")
            case .kannada:  return L("language.kannada")
            case .malayalam: return L("language.malayalam")
            case .marathi:  return L("language.marathi")
            case .bengali:  return L("language.bengali")
            case .gujarati: return L("language.gujarati")
            case .punjabi:  return L("language.punjabi")
            case .urdu:     return L("language.urdu")
            }
        }
    }

    private var relayBinding: Binding<Bool> {
        Binding(get: { app.relayManager.isRelayActive },
                set: { newValue in Task { await app.relayManager.setRelay(newValue) } })
    }

    private var demoBinding: Binding<Bool> {
        Binding(get: { app.demoController.isDemoMode },
                set: { app.demoController.setDemo($0) })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                ResilixTheme.backgroundPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: ResilixTheme.space24) {
                        settingsHeader

                        SettingsSection(title: "ACCOUNT") {
                            SettingsNavRow(icon: "person.circle", title: L("Profile")) {
                                ProfileView()
                            }
                            Divider().padding(.leading, 54)
                            SettingsNavRow(icon: "hand.raised.fill", title: L("Privacy")) {
                                PrivacyView()
                            }
                            Divider().padding(.leading, 54)
                            SettingsNavRow(icon: "bell.fill", title: L("Notifications")) {
                                NotificationsSettingsView()
                            }
                            Divider().padding(.leading, 54)
                            SettingsLogoutRow()
                        }

                        SettingsSection(title: "NETWORK") {
                            SettingsNavRow(icon: "point.3.connected.trianglepath.dotted", title: L("Mesh Settings")) {
                                MeshSettingsView()
                            }
                            Divider().padding(.leading, 54)
                            SettingsToggleRow(icon: "arrow.triangle.2.circlepath", title: L("Relay Mode"), isOn: relayBinding)
                            Divider().padding(.leading, 54)
                            SettingsNavRow(icon: "sparkles", title: L("Offline AI")) {
                                OfflineAISettingsView()
                            }
                            Divider().padding(.leading, 54)
                            SettingsNavRow(icon: "map.fill", title: L("Maps")) {
                                MapSettingsView()
                            }
                        }

                        SettingsSection(title: "APP") {
                            SettingsActionRow(icon: "globe", title: L("Language"), value: language.rawValue) {
                                showLanguagePicker = true
                            }
                            Divider().padding(.leading, 54)
                            SettingsActionRow(icon: "moon.circle.fill", title: L("Appearance"), value: Appearance(rawValue: appearance)?.label ?? appearance) {
                                showAppearance = true
                            }
                            Divider().padding(.leading, 54)
                            SettingsToggleRow(icon: "play.rectangle", title: L("Demo Mode"), isOn: demoBinding)
                        }

                        if app.demoController.isDemoMode {
                            Text(L("Demo Mode is ON — all devices, messages and map nodes are simulated."))
                                .font(ResilixTheme.captionFont)
                                .foregroundStyle(ResilixTheme.brandAmber)
                                .padding(.horizontal, ResilixTheme.space20)
                        }

                        versionFooter
                    }
                    .padding(.top, ResilixTheme.space16)
                    .padding(.bottom, 120)
                }
            }
            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showLanguagePicker) {
            LanguagePickerView(selectedLanguage: $language)
                .environmentObject(app)
        }
        .onChange(of: language) { _, newValue in
            LocalizationManager.shared.apply(newValue.rawValue)
            Task { await app.updateSettings { $0.language = newValue.rawValue } }
        }
        .confirmationDialog(L("Appearance"), isPresented: $showAppearance, titleVisibility: .visible) {
            ForEach(Appearance.allCases) { option in
                Button(option.label) { appearance = option.rawValue }
            }
            Button(L("Cancel"), role: .cancel) {}
        }
    }

    // MARK: Header — "Settings" title + close button
    private var settingsHeader: some View {
        HStack {
            Text(L("Settings"))
                .font(ResilixTheme.largeTitleFont)
                .foregroundStyle(ResilixTheme.textPrimary)
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(ResilixTheme.textSecondary)
                    .frame(width: 34, height: 34)
                    .background(ResilixTheme.glassBackground)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(ResilixTheme.glassBorder, lineWidth: 0.8))
            }
            .pressScale()
            accessibilityLabel(Text(L("Close settings")))
        }
        .padding(.horizontal, ResilixTheme.space20)
        .padding(.top, ResilixTheme.space8)
    }

    private var versionFooter: some View {
        HStack {
            Spacer()
            Text(L("Resilix 1.0.0"))
                .font(ResilixTheme.captionFont)
                .foregroundStyle(ResilixTheme.textTertiary)
            Spacer()
        }
        .padding(.top, ResilixTheme.space8)
    }
}

// MARK: - Settings section container (liquid glass)
struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: ResilixTheme.space8) {
            Text(title)
                .font(ResilixTheme.sectionHeaderFont)
                .tracking(1.0)
                .foregroundStyle(ResilixTheme.textTertiary)
                .padding(.leading, 28)
            VStack(spacing: 0) { content }
                .liquidGlassRounded(cornerRadius: ResilixTheme.cornerRadiusLarge)
                .padding(.horizontal, ResilixTheme.space20)
        }
    }
}

// MARK: - Row building blocks
private struct SettingsIcon: View {
    let systemName: String
    var color: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension SettingsIcon {
    /// Distinct muted color per icon based on its purpose (dulled, not bright)
    static func color(for systemName: String) -> Color {
        switch systemName {
        case "person.circle", "person.fill":
            return Color(hex: "5B7A99")              // muted blue - account
        case "hand.raised.fill":
            return Color(hex: "7A6E91")              // muted purple - privacy
        case "bell.fill":
            return Color(hex: "9A8A5E")              // muted amber - notifications
        case "rectangle.portrait.and.arrow.right":
            return Color(hex: "9E5A5A")              // muted red - logout
        case "point.3.connected.trianglepath.dotted", "dot.radiowaves.left.and.right", "waveform.path.ecg":
            return Color(hex: "5E8D96")              // muted cyan - mesh/network
        case "arrow.triangle.2.circlepath":
            return Color(hex: "5F8F86")              // muted teal - relay
        case "sparkles", "ladybug.fill":
            return Color(hex: "8E6E80")              // muted pink - AI/debug
        case "map.fill":
            return Color(hex: "5E8A76")              // muted green - maps
        case "globe":
            return Color(hex: "6E769B")              // muted indigo - language
        case "moon.circle.fill", "moon":
            return Color(hex: "6E7986")              // muted slate - appearance
        case "play.rectangle":
            return Color(hex: "9A7A5B")              // muted orange - demo mode
        case "bubble.left.fill":
            return Color(hex: "5B7A99")              // muted blue - messages
        case "exclamationmark.triangle.fill":
            return Color(hex: "9E5A5A")              // muted red - SOS
        default:
            return ResilixTheme.brandBlueGray
        }
    }
}

struct SettingsNavRow<Destination: View>: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @ViewBuilder var destination: Destination

    var body: some View {
        NavigationLink(destination: destination) {
            HStack(spacing: ResilixTheme.space12) {
                SettingsIcon(systemName: icon, color: SettingsIcon.color(for: icon))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ResilixTheme.font(16, .semibold))
                        .foregroundStyle(ResilixTheme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(ResilixTheme.captionFont)
                            .foregroundStyle(ResilixTheme.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ResilixTheme.textTertiary)
            }
            .padding(.horizontal, ResilixTheme.space16)
            .padding(.vertical, ResilixTheme.space12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsActionRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ResilixTheme.space12) {
                SettingsIcon(systemName: icon, color: SettingsIcon.color(for: icon))
                Text(title)
                    .font(ResilixTheme.font(16, .semibold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                Spacer()
                if let value {
                    Text(value)
                        .font(ResilixTheme.font(14, .regular))
                        .foregroundStyle(ResilixTheme.textSecondary)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ResilixTheme.textTertiary)
            }
            .padding(.horizontal, ResilixTheme.space16)
            .padding(.vertical, ResilixTheme.space12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct SettingsToggleRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: ResilixTheme.space12) {
            SettingsIcon(systemName: icon, color: SettingsIcon.color(for: icon))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ResilixTheme.font(16, .semibold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                if let subtitle {
                    Text(subtitle)
                        .font(ResilixTheme.captionFont)
                        .foregroundStyle(ResilixTheme.textSecondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(ResilixTheme.successGreen)
        }
        .padding(.horizontal, ResilixTheme.space16)
        .padding(.vertical, ResilixTheme.space12)
    }
}

struct SettingsLogoutRow: View {
    @EnvironmentObject var app: ResilixAppModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("isAuthenticated") private var isAuthenticated = false
    @State private var showConfirm = false

    var body: some View {
        Button { showConfirm = true } label: {
            HStack(spacing: ResilixTheme.space12) {
                SettingsIcon(systemName: "rectangle.portrait.and.arrow.right", color: SettingsIcon.color(for: "rectangle.portrait.and.arrow.right"))
                Text(L("Log Out"))
                    .font(ResilixTheme.font(16, .semibold))
                    .foregroundStyle(ResilixTheme.emergencyRed)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(ResilixTheme.textTertiary)
            }
            .padding(.horizontal, ResilixTheme.space16)
            .padding(.vertical, ResilixTheme.space12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .alert(L("Log Out"), isPresented: $showConfirm) {
            Button(L("Log Out"), role: .destructive) {
                isAuthenticated = false
                dismiss()
            }
            Button(L("Cancel"), role: .cancel) {}
        } message: {
            Text(L("Are you sure you want to log out?"))
        }
    }
}

// MARK: - Sub-pages

struct NotificationsSettingsView: View {
    @AppStorage("notifyMessages") private var notifyMessages = true
    @AppStorage("notifySOS") private var notifySOS = true
    @AppStorage("notifyMeshEvents") private var notifyMeshEvents = false

    var body: some View {
        Form {
            SettingsToggleRow(icon: "bubble.left.fill", title: L("New Messages"), isOn: $notifyMessages)
            SettingsToggleRow(icon: "exclamationmark.triangle.fill", title: L("SOS Alerts"), isOn: $notifySOS)
            SettingsToggleRow(icon: "dot.radiowaves.left.and.right", title: L("Mesh Events"), isOn: $notifyMeshEvents)
        }
        .scrollContentBackground(.hidden)
        .background(ResilixTheme.backgroundPrimary)
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MeshSettingsView: View {
    @EnvironmentObject var app: ResilixAppModel
    @AppStorage("autoRelay") private var autoRelay = false
    @AppStorage("showDebugInfo") private var showDebugInfo = false

    var body: some View {
        Form {
            SettingsToggleRow(icon: "arrow.triangle.2.circlepath", title: L("Auto-relay when connected"), isOn: $autoRelay)
            SettingsToggleRow(icon: "ladybug.fill", title: L("Show Debug Info"), isOn: $showDebugInfo)
            SettingsNavRow(icon: "waveform.path.ecg", title: L("Network Diagnostics")) {
                DiagnosticsView()
            }
        }
        .scrollContentBackground(.hidden)
        .background(ResilixTheme.backgroundPrimary)
        .navigationTitle("Mesh Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct OfflineAISettingsView: View {
    @EnvironmentObject var app: ResilixAppModel

    var body: some View {
        Form {
            Section {
                SettingsToggleRow(icon: "sparkles",
                                  title: L("Keep conversation history"),
                                  subtitle: L("Stored on this device only"),
                                  isOn: Binding(
                                    get: { app.settings.aiConversationPersistence },
                                    set: { newValue in Task { await app.updateSettings { $0.aiConversationPersistence = newValue } } }
                                  ))
            }

            Section(header: Text(L("Active model"))) {
                HStack {
                    Text(app.aiService.activeModel?.displayName ?? "None")
                        .foregroundStyle(ResilixTheme.textPrimary)
                    Spacer()
                    Text(statusText)
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.textTertiary)
                }
                NavigationLink {
                    AIModelManagerView()
                        .environmentObject(app)
                } label: {
                    Label(L("Manage models"), systemImage: "cpu")
                }
            }

            Section {
                Button(L("Clear conversation")) {
                    Task { await app.aiService.clearConversation() }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(ResilixTheme.backgroundPrimary)
        .navigationTitle("Offline AI")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var statusText: String {
        guard let model = app.aiService.activeModel else { return "—" }
        switch model.availability {
        case .ready: return L("Ready")
        case .notInstalled: return L("Not installed")
        case .runtimeUnavailable: return L("No runtime")
        case .unusable: return L("Unusable")
        }
    }
}

struct MapSettingsView: View {
    @EnvironmentObject var app: ResilixAppModel
    @State private var showImporter = false
    @State private var message: String?

    var body: some View {
        Form {
            Section(header: Text(L("Installed packs"))) {
                if app.mapPackService.packs.isEmpty {
                    Text(L("No offline map is installed. The map screen uses the online Apple tiles until a pack is imported."))
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.textSecondary)
                } else {
                    ForEach(app.mapPackService.packs) { pack in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(pack.name)
                                    .foregroundStyle(ResilixTheme.textPrimary)
                                Spacer()
                                if app.mapPackService.activePackID == pack.id {
                                    ResilixStatusBadge(text: "Active", color: ResilixTheme.successGreen)
                                }
                            }
                            Text(L("map.zoom") + " \(pack.minZoom)–\(pack.maxZoom) · \(ByteCountFormatter.string(fromByteCount: Int64(pack.byteCount), countStyle: .file))")
                                .font(.caption2)
                                .foregroundStyle(ResilixTheme.textTertiary)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets {
                            let pack = app.mapPackService.packs[index]
                            Task { await app.mapPackService.deletePack(pack.id) }
                        }
                    }
                }
            }

            Section {
                Button {
                    showImporter = true
                } label: {
                    Label(L("Import map pack"), systemImage: "square.and.arrow.down")
                }
                Text(L("settings.storage.used") + ": \(ByteCountFormatter.string(fromByteCount: Int64(app.mapPackService.storageUsedBytes), countStyle: .file))")
                    .font(.caption)
                    .foregroundStyle(ResilixTheme.textTertiary)
            }
        }
        .scrollContentBackground(.hidden)
        .background(ResilixTheme.backgroundPrimary)
        .navigationTitle("Maps")
        .navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $showImporter,
                      allowedContentTypes: [.data],
                      allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    Task {
                        do {
                            _ = try await app.mapPackService.importPack(from: url)
                            message = L("The map pack was imported.")
                        } catch {
                            message = error.localizedDescription
                        }
                    }
                }
            case .failure:
                message = L("The map pack could not be opened.")
            }
        }
        .alert(L("Maps"), isPresented: .constant(message != nil), presenting: message) { _ in
            Button(L("OK")) { message = nil }
        } message: { text in
            Text(text)
        }
    }
}

// MARK: - Language Picker
struct LanguagePickerView: View {
    @Environment(\.dismiss) var dismiss
    @Binding var selectedLanguage: SettingsView.Language

    var body: some View {
        NavigationStack {
            ZStack {
                ResilixTheme.backgroundPrimary.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(SettingsView.Language.allCases.enumerated()), id: \.element) { index, lang in
                            Button {
                                selectedLanguage = lang
                                LocalizationManager.shared.apply(lang.rawValue)
                                dismiss()
                            } label: {
                                HStack(spacing: ResilixTheme.space12) {
                                    Text(lang.label)
                                        .font(ResilixTheme.font(16, .medium))
                                        .foregroundStyle(ResilixTheme.textPrimary)
                                    Spacer()
                                    if selectedLanguage == lang {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(ResilixTheme.brandCyan)
                                    }
                                }
                                .padding(.horizontal, ResilixTheme.space20)
                                .padding(.vertical, ResilixTheme.space12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if index < SettingsView.Language.allCases.count - 1 {
                                Divider().overlay(ResilixTheme.separator.opacity(0.5)).padding(.leading, ResilixTheme.space20)
                            }
                        }
                    }
                    .background(ResilixTheme.surfacePrimary)
                    .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                            .stroke(ResilixTheme.separator.opacity(0.6), lineWidth: 0.6)
                    )
                    .padding(.horizontal, ResilixTheme.space20)
                    .padding(.top, ResilixTheme.space16)
                }
            }
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(L("Done")) { dismiss() }
                        .font(ResilixTheme.font(15, .semibold))
                }
            }
        }
    }
}

#Preview { SettingsView().environmentObject(ResilixAppModel()) }
