import SwiftUI
import Foundation

// MARK: - Home / Chats
// The main screen: messaging-first UI built around the mesh network.
// Structure: top bar (logo mark · mesh status pill · language · settings),
// greeting, "Chats" section, WhatsApp-style chat list, floating compose button.

struct HomeView: View {
    @EnvironmentObject var app: ResilixAppModel
    @Binding var showSOS: Bool
    @State private var showSettings = false
    @State private var showLanguage = false
    @State private var searchText = ""
    @State private var peers: [MeshNode] = []
    @AppStorage("language") private var language: SettingsView.Language = .english
    @State private var meshConnected = true

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ResilixTheme.backgroundPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        topBar
                            .padding(.top, ResilixTheme.space8)
                            .padding(.bottom, ResilixTheme.space20)

                        Text(L("Chats"))
                            .font(ResilixTheme.font(28, .bold))
                            .foregroundStyle(ResilixTheme.textPrimary)
                            .padding(.horizontal, ResilixTheme.space20)
                            .padding(.bottom, ResilixTheme.space12)

                        searchBar
                            .padding(.bottom, ResilixTheme.space12)

                        chatList
                    }
                    .padding(.bottom, ResilixTheme.space24)
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .fullScreenCover(isPresented: $showSettings) {
                SettingsView().environmentObject(app)
            }
            .sheet(isPresented: $showLanguage) {
                LanguagePickerView(selectedLanguage: $language)
                    .presentationDetents([.medium, .large])
            }
            .task { await refreshPeers() }
            .refreshable { await refreshPeers() }
        }
    }

// MARK: - Top bar: logo mark · mesh status pill · language · settings
    private var topBar: some View {
        HStack(spacing: 8) {
            LogoView(variant: .mark, height: 88)

            Spacer(minLength: 8)

            MeshStatusPill(connected: meshConnected)
                .padding(.trailing, 4)
                .onTapGesture {
                    withAnimation(ResilixTheme.animationMedium) {
                        meshConnected.toggle()
                    }
                }

            GlassCircleButton(systemImage: "globe", size: 32) { showLanguage = true }
                .accessibilityLabel(Text(L("Language")))

            GlassCircleButton(systemImage: "gearshape", size: 32) { showSettings = true }
                .accessibilityLabel(Text(L("Settings")))
        }
        .padding(.horizontal, ResilixTheme.space16)
    }

    // MARK: - Search bar
    private var searchBar: some View {
        HStack(spacing: ResilixTheme.space8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(ResilixTheme.textTertiary)
            TextField(L("Search"), text: $searchText)
                .font(ResilixTheme.font(15, .regular))
                .foregroundStyle(ResilixTheme.textPrimary)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button { searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ResilixTheme.textTertiary)
                }
                .accessibilityLabel(Text(L("Clear search")))
            }
        }
        .padding(.horizontal, ResilixTheme.space16)
        .padding(.vertical, ResilixTheme.space10)
        .liquidGlassRounded(cornerRadius: ResilixTheme.cornerRadiusMedium, interactive: true)
        .padding(.horizontal, ResilixTheme.space20)
    }

    // MARK: - Chat list
    private var chatList: some View {
        Group {
            if filteredConversations.isEmpty {
                EmptyStateView(title: searchText.isEmpty ? L("No conversations") : L("No results"),
                               subtitle: searchText.isEmpty ? L("Find nearby Resilix users to start communicating.") : String(format: L("No chats match \"%@\"."), searchText),
                               icon: "bubble.left.and.bubble.right")
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(filteredConversations) { conversation in
                        NavigationLink(destination: MessageThreadView(message: conversation.message)) {
                            ConversationRow(conversation: conversation)
                        }
                        .buttonStyle(.plain)
                        if conversation.id != filteredConversations.last?.id {
                            Rectangle()
                                .fill(Color(hex: "2A2A2E"))
                                .frame(height: 0.5)
                                .padding(.leading, 84)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data
    struct Conversation: Identifiable {
        let id: String
        let name: String
        let preview: String
        let date: Date
        let unread: Int
        let online: Bool
        let mesh: MeshBadge?
        let signal: Int          // 0–3 mesh signal strength
        let avatarColor: Color
        let message: MeshMessage
    }

    enum MeshBadge: String {
        case direct = "Direct"
        case oneHop = "1 Hop"
        case twoHops = "2 Hops"
        case relayed = "Relayed"
        case waiting = "Waiting"

        /// Localized label shown under the conversation preview.
        var title: String {
            switch self {
            case .direct: return L("Direct")
            case .oneHop: return L("1 Hop")
            case .twoHops: return L("2 Hops")
            case .relayed: return L("Relayed")
            case .waiting: return L("Waiting")
            }
        }

        var color: Color {
            switch self {
            case .direct: return ResilixTheme.brandCyan
            case .oneHop, .twoHops: return ResilixTheme.brandBlueGray
            case .relayed: return ResilixTheme.brandAmber
            case .waiting: return ResilixTheme.textTertiary
            }
        }
    }

    private var conversations: [Conversation] {
        // Demo mode: always show simulated people messaging on the mesh
        if app.demoController.isDemoMode { return Self.demoConversations }
        let base = app.messageService.messages
        return base.map { message in
            Conversation(
                id: message.id,
                name: message.threadID,
                preview: message.text,
                date: message.createdAt,
                unread: 0,
                online: message.deliveryState == .delivered,
                mesh: meshBadge(for: message.lastRoute),
                signal: message.deliveryState == .delivered ? 3 : 1,
                avatarColor: AvatarView.color(for: message.threadID),
                message: message
            )
        }
    }

    private func meshBadge(for route: String?) -> MeshBadge? {
        guard let route else { return nil }
        switch route.lowercased() {
        case "direct": return .direct
        case L("1 hop"): return .oneHop
        case L("2 hops"): return .twoHops
        case "relayed": return .relayed
        case "waiting": return .waiting
        default: return nil
        }
    }

    private var filteredConversations: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return conversations }
        return conversations.filter {
            $0.name.localizedCaseInsensitiveContains(query) ||
            $0.preview.localizedCaseInsensitiveContains(query)
        }
    }



    private func refreshPeers() async {
        var all: [MeshNode] = []
        for t in app.meshController.availableTransports { all.append(contentsOf: t.discoveredPeers) }
        if app.demoController.isDemoMode && all.isEmpty {
            all = [
                MeshNode(id: "1", alias: "Alex", lastSeen: Date(), isRelay: false),
                MeshNode(id: "2", alias: "Sam", lastSeen: Date(), isRelay: true),
                MeshNode(id: "3", alias: "Jordan", lastSeen: Date(), isRelay: false),
                MeshNode(id: "4", alias: "Maya", lastSeen: Date(), isRelay: true),
                MeshNode(id: "5", alias: "Taylor", lastSeen: Date(), isRelay: false),
                MeshNode(id: "6", alias: "Chris", lastSeen: Date(), isRelay: false),
            ]
        }
        peers = all
    }

    // MARK: - Example conversations (Demo Mode — clearly simulated)
    static var demoConversations: [Conversation] {
        func msg(_ id: String, _ name: String, _ text: String, _ age: TimeInterval, _ route: String?, _ state: DeliveryState) -> MeshMessage {
            MeshMessage(id: id, packetID: nil, threadID: name, sourceNodeID: name, destinationNodeID: "YOU",
                        text: text, createdAt: Date().addingTimeInterval(-age),
                        deliveryState: state, expirySeconds: nil, lastRoute: route, priority: .normal)
        }
        func conv(_ id: String, _ name: String, _ text: String, _ age: TimeInterval, _ unread: Int, _ online: Bool, _ mesh: MeshBadge?, _ signal: Int, _ color: Color, _ route: String?, _ state: DeliveryState) -> Conversation {
            Conversation(id: id, name: name, preview: text, date: Date().addingTimeInterval(-age),
                         unread: unread, online: online, mesh: mesh, signal: signal, avatarColor: color,
                         message: msg(id, name, text, age, route, state))
        }
        return [
            conv("1", "Sarah K.", L("Are you safe? We're at the community shelter o…"), 120, 2, true, .direct, 3, Color(hex: "A855B7"), L("Direct"), .delivered),
            conv("2", L("Rescue Team Alpha"), L("Route via Oak St clear. Proceed to checkpoint…"), 480, 1, true, .relayed, 2, Color(hex: "D26714"), L("Relayed"), .relaying),
            conv("3", "Marcus D.", L("I have medical supplies at grid 4-C"), 900, 0, true, .oneHop, 3, Color(hex: "6D49C7"), L("1 hop"), .delivered),
            conv("4", L("Downtown Group"), L("Power restored at 5th Ave shelter, 47 people…"), 3600, 0, true, .relayed, 1, Color(hex: "0E9F6E"), L("Relayed"), .relaying),
            conv("5", "Emma & Tom", L("Come to our location — water and food available"), 7200, 0, false, .waiting, 0, Color(hex: "BE3B82"), L("Waiting"), .queued),
            conv("6", L("City Emergency"), L("All clear signal received from sector 7"), 18000, 0, true, .twoHops, 2, Color(hex: "243B7A"), L("2 hops"), .delivered),
            conv("7", "Nina P.", L("Found a working generator, sharing fuel at block D"), 21600, 3, true, .direct, 3, Color(hex: "0892B0"), L("Direct"), .delivered),
            conv("8", L("Field Medic Unit"), L("Triage station moved to Central Park gates"), 43200, 0, true, .relayed, 1, Color(hex: "C73838"), L("Relayed"), .relaying),
        ]
    }
}

// MARK: - Mesh status pill (compact, single line)
struct MeshStatusPill: View {
    let connected: Bool

    var body: some View {
        HStack(spacing: ResilixTheme.space4) {
            Circle()
                .fill(connected ? ResilixTheme.successGreen : ResilixTheme.brandAmber)
                .frame(width: 5, height: 5)
            Text(connected ? L("Mesh Connected") : L("Mesh Disconnected"))
                .font(ResilixTheme.font(10, .semibold))
                .foregroundStyle(connected ? ResilixTheme.successGreen : ResilixTheme.brandAmber)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, ResilixTheme.space12)
        .frame(height: 30)
        .liquidGlassCapsule(interactive: false)
        .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
        .shadow(color: ResilixTheme.cyanGlow, radius: 6, x: 0, y: 0)
        .animation(ResilixTheme.animationMedium, value: connected)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Circular Liquid Glass button
struct GlassCircleButton: View {
    let systemImage: String
    var size: CGFloat = 38
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.42, weight: .medium))
                .foregroundStyle(ResilixTheme.textPrimary)
                .frame(width: size, height: size)
                .liquidGlassCircle()
                .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)
                .shadow(color: ResilixTheme.cyanGlow, radius: 6, x: 0, y: 0)
        }
        .pressScale()
    }
}

// MARK: - Avatar with initials + optional mesh presence dot
struct AvatarView: View {
    let name: String
    var size: CGFloat = 52
    var online: Bool = true
    var color: Color? = nil

    static func color(for name: String) -> Color {
        let palette: [Color] = [
            Color(hex: "A855B7"), // fuchsia (dim)
            Color(hex: "6D49C7"), // deep purple (dim)
            Color(hex: "8395D8"), // lavender blue (dim)
            Color(hex: "243B7A"), // navy (dim)
            Color(hex: "BE3B82"), // hot pink (dim)
            Color(hex: "9D2D63"), // magenta (dim)
            Color(hex: "2A9BD9"), // sky blue (dim)
            Color(hex: "0892B0"), // cyan (dim)
            Color(hex: "0F9488"), // teal (dim)
            Color(hex: "2BB383"), // mint (dim)
            Color(hex: "0E9F6E"), // green (dim)
            Color(hex: "6BA314"), // lime (dim)
            Color(hex: "5C3022"), // dark brown (dim)
            Color(hex: "8C6FC4"), // mauve (dim)
            Color(hex: "7747D6"), // violet (dim)
            Color(hex: "4F52D1"), // indigo (dim)
            Color(hex: "D26714"), // orange (dim)
            Color(hex: "C73838"), // red (dim)
            Color(hex: "7F1818"), // dark red (dim)
        ]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        return palette[abs(hash) % palette.count]
    }

    /// Gradient pair based on name hash — vibrant but slightly dimmed for dark mode
    static func gradient(for name: String) -> LinearGradient {
        let palette: [(Color, Color)] = [
            (Color(hex: "A855B7"), Color(hex: "7E2D8E")), // fuchsia
            (Color(hex: "6D49C7"), Color(hex: "4F2D9C")), // deep purple
            (Color(hex: "8395D8"), Color(hex: "4F58C2")), // lavender blue
            (Color(hex: "243B7A"), Color(hex: "1A2D63")), // navy
            (Color(hex: "BE3B82"), Color(hex: "8E2A63")), // hot pink
            (Color(hex: "9D2D63"), Color(hex: "6B1F45")), // magenta
            (Color(hex: "2A9BD9"), Color(hex: "0F6FA0")), // sky blue
            (Color(hex: "0892B0"), Color(hex: "075F73")), // cyan
            (Color(hex: "0F9488"), Color(hex: "0B6059")), // teal
            (Color(hex: "2BB383"), Color(hex: "1F7E5C")), // mint
            (Color(hex: "0E9F6E"), Color(hex: "086446")), // green
            (Color(hex: "6BA314"), Color(hex: "4D7A0E")), // lime
            (Color(hex: "5C3022"), Color(hex: "3F1F15")), // dark brown
            (Color(hex: "8C6FC4"), Color(hex: "5E4898")), // mauve
            (Color(hex: "7747D6"), Color(hex: "5028A0")), // violet
            (Color(hex: "4F52D1"), Color(hex: "2E308A")), // indigo
            (Color(hex: "D26714"), Color(hex: "9A4A0E")), // orange
            (Color(hex: "C73838"), Color(hex: "8E2828")), // red
            (Color(hex: "7F1818"), Color(hex: "5E1111")), // dark red
        ]
        let hash = name.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) }
        let pair = palette[abs(hash) % palette.count]
        return LinearGradient(
            colors: [pair.0, pair.1],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var initials: String {
        let parts = name.split(separator: " ").filter { $0 != "&" }
        let first = parts.first?.prefix(1) ?? "?"
        let second = parts.count > 1 ? parts[1].prefix(1) : ""
        return (first + second).uppercased()
    }

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                Circle()
                    .fill(AvatarView.gradient(for: name))
                    .frame(width: size, height: size)
                Text(initials)
                    .font(ResilixTheme.font(size * 0.36, .bold))
                    .foregroundStyle(.white)
            }
            Circle()
                .fill(online ? ResilixTheme.successGreen : ResilixTheme.textTertiary)
                .frame(width: size * 0.22, height: size * 0.22)
                .overlay(Circle().stroke(ResilixTheme.backgroundPrimary, lineWidth: 2))
                .offset(x: 1, y: 1)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Chat row (WhatsApp-style hierarchy)
struct ConversationRow: View {
    let conversation: HomeView.Conversation

    /// Compact timestamp like "2m", "15m", "1h", "5h"
    private var shortTime: String {
        let interval = Date().timeIntervalSince(conversation.date)
        let minutes = Int(interval / 60)
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes)m" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h" }
        return "\(hours / 24)d"
    }

    private var signalColor: Color {
        switch conversation.signal {
        case 3: return ResilixTheme.successGreen
        case 2: return ResilixTheme.brandAmber
        case 1: return ResilixTheme.brandBlueGray
        default: return ResilixTheme.textTertiary
        }
    }

    private var signalLabel: String {
        switch conversation.signal {
        case 3: return L("signal.strong")
        case 2: return L("signal.good")
        case 1: return L("signal.weak")
        default: return L("No link")
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: ResilixTheme.space12) {
            AvatarView(name: conversation.name,
                       online: conversation.online,
                       color: conversation.avatarColor)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.name)
                        .font(ResilixTheme.font(16, .semibold))
                        .foregroundStyle(ResilixTheme.textPrimary)
                        .lineLimit(1)
                    Spacer(minLength: ResilixTheme.space8)
                    Text(shortTime)
                        .font(ResilixTheme.font(12, .regular))
                        .foregroundStyle(conversation.unread > 0 ? ResilixTheme.brandCyan : ResilixTheme.textTertiary)
                }
                HStack(alignment: .center, spacing: ResilixTheme.space8) {
                    Text(conversation.preview)
                        .font(ResilixTheme.font(14, .regular))
                        .foregroundStyle(ResilixTheme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: ResilixTheme.space8)
                    if conversation.unread > 0 {
                        UnreadBadge(count: conversation.unread)
                    }
                }

                // Mesh info line: relay badge · online status · signal strength
                HStack(spacing: ResilixTheme.space8) {
                    if let mesh = conversation.mesh {
                        HStack(spacing: 4) {
                            Image(systemName: mesh == .relayed ? "point.3.connected.trianglepath.dotted" : "wave.3.right")
                                .font(.system(size: 8, weight: .bold))
                            Text(mesh.title)
                                .font(ResilixTheme.font(10, .semibold))
                        }
                        .foregroundStyle(mesh.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(mesh.color.opacity(0.14))
                        .clipShape(Capsule())
                    }

                    HStack(spacing: 3) {
                        Circle()
                            .fill(conversation.online ? ResilixTheme.successGreen : ResilixTheme.textTertiary)
                            .frame(width: 5, height: 5)
                        Text(conversation.online ? L("Online") : L("Offline"))
                            .font(ResilixTheme.font(10, .medium))
                    }
                    .foregroundStyle(conversation.online ? ResilixTheme.successGreen : ResilixTheme.textTertiary)

                    Spacer(minLength: 0)

                    HStack(spacing: 3) {
                        Image(systemName: "cellularbars", variableValue: Double(conversation.signal) / 3.0)
                            .font(.system(size: 11, weight: .medium))
                        Text(signalLabel)
                            .font(ResilixTheme.font(10, .medium))
                    }
                    .foregroundStyle(signalColor)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, ResilixTheme.space20)
        .padding(.vertical, ResilixTheme.space12)
        .contentShape(Rectangle())
    }
}

// MARK: - Unread badge
struct UnreadBadge: View {
    let count: Int
    var body: some View {
        Text(verbatim: "\(count)")
            .font(ResilixTheme.font(12, .bold))
            .foregroundStyle(ResilixTheme.textOnAccent)
            .frame(minWidth: 22, minHeight: 22)
            .padding(.horizontal, 5)
            .background(ResilixTheme.brandCyan)
            .clipShape(Capsule())
            .shadow(color: ResilixTheme.cyanGlowStrong, radius: 5, x: 0, y: 0)
            .shadow(color: Color.black.opacity(0.2), radius: 3, x: 0, y: 1)
    }
}

#Preview {
    HomeView(showSOS: .constant(false)).environmentObject(ResilixAppModel())
}
