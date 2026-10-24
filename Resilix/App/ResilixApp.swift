// xcode: set sdk=iOS

import SwiftUI

// Cinematic launch: black → cyan seed point → nodes → connections → logo fade/zoom (~2s).
@main
struct ResilixApp: App {
    @StateObject private var appModel = ResilixAppModel()
    @AppStorage("appearance") private var appearance: String = "System"
    @AppStorage("isAuthenticated") private var isAuthenticated = false
    @State private var hasResetAuth = false

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "Light": return .light
        case "Dark": return .dark
        default: return nil
        }
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isAuthenticated {
                    RootView()
                        .environmentObject(appModel)
                } else {
                    WelcomeFlowView(isAuthenticated: $isAuthenticated)
                        .environmentObject(appModel)
                }
            }
            .tint(ResilixTheme.brandCyan)
            .preferredColorScheme(colorScheme) // respects Settings → Appearance
            .onAppear {
                // Ensure login appears first on every fresh launch
                if !hasResetAuth {
                    hasResetAuth = true
                    isAuthenticated = false
                }
            }
        }
    }
}

// MARK: - Welcome flow — unified slider TabView, no redirect
struct WelcomeFlowView: View {
    @Binding var isAuthenticated: Bool
    @State private var showLogin = false
    @State private var showCreate = false
    @State private var isGuest = false

    var body: some View {
        WelcomeView(showLogin: $showLogin, showCreate: $showCreate, isGuest: $isGuest)
            .onChange(of: isGuest) { _, newValue in if newValue { completeAuth() } }
            .onChange(of: showLogin) { _, newValue in if newValue { completeAuth() } }
            .onChange(of: showCreate) { _, newValue in if newValue { completeAuth() } }
            .onReceive(NotificationCenter.default.publisher(for: .authSuccess)) { _ in
                completeAuth()
            }
    }

    private func completeAuth() {
        withAnimation(ResilixTheme.animationMedium) {
            isAuthenticated = true
        }
        showLogin = false
        showCreate = false
        isGuest = false
    }
}

@MainActor
class ResilixAppModel: ObservableObject {
    let persistence = PersistenceController.shared
    let routingEngine = MeshRoutingEngine()
    
    // Production transports only - MockMeshTransport is DEBUG only
    #if DEBUG
    let mockTransport = MockMeshTransport()
    #endif
    
    lazy var transports: [any MeshTransport] = {
        var t: [any MeshTransport] = [BluetoothTransport(), PeerToPeerWiFiTransport(), WiFiAwareTransport()]
        #if DEBUG
        t.insert(mockTransport, at: 0)
        #endif
        return t
    }()
    
    lazy var meshController: MeshController = MeshController(routingEngine: routingEngine, transports: transports)
    lazy var relayManager = RelayManager()
    lazy var messageService: MessageService = MessageService(meshController: meshController)
    lazy var sosService: SOSService = SOSService(meshController: meshController)
    lazy var resourceService = ResourceService()
    lazy var permissionService = PermissionService()
    lazy var diagnosticsService = DiagnosticsService()
    
    #if DEBUG
    lazy var demoController: DemoModeController = DemoModeController(meshController: meshController, mock: mockTransport)
    #else
    lazy var demoController: DemoModeController = DemoModeController(meshController: meshController, mock: MockMeshTransport())
    #endif
    
    lazy var lifecycle = AppLifecycleService()

    @Published var settings = AppSettings()
    @Published var nodeID: String = ""

    init() {
        Task { @MainActor in
            self.settings = await persistence.loadSettings()
            self.nodeID = await loadOrCreateNodeID()
            try? await SecurityManager().setupIdentityIfNeeded(nodeID: nodeID)
            
            // Configure lifecycle
            lifecycle.configure(meshController: meshController, relayManager: relayManager)
            lifecycle.onLaunch()
            
            await meshController.start()
            
            #if DEBUG
            if settings.isDemoMode {
                await demoController.startDemo()
            }
            #endif
        }
    }
    
    private func loadOrCreateNodeID() async -> String {
        if let existing = UserDefaults.standard.string(forKey: "resilix.nodeID") {
            return existing
        }
        let newID = UUID().uuidString
        UserDefaults.standard.set(newID, forKey: "resilix.nodeID")
        return newID
    }
}

struct RootView: View {
    @EnvironmentObject var model: ResilixAppModel
    @State private var selectedTab = 0
    @State private var showOnboarding = false
    @State private var showSOS = false

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(showSOS: $showSOS)
                .tabItem { Label("Chats", systemImage: "bubble.left.and.bubble.right") }
                .tag(0)
            NearbyView()
                .tabItem { Label("Nearby", systemImage: "antenna.radiowaves.left.and.right") }
                .tag(1)
            MeshView()
                .tabItem { Label("Mesh", systemImage: "point.3.connected.trianglepath.dotted") }
                .tag(2)
            SurvivalMapView()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(3)
            AssistView()
                .tabItem { Label("Assist", systemImage: "bolt") }
                .tag(4)
        }
        .tint(ResilixTheme.brandCyan)
        .background(ResilixTheme.backgroundPrimary.ignoresSafeArea())
        .sheet(isPresented: $showOnboarding) { OnboardingView() }
        .sheet(isPresented: $showSOS) { SOSView() }
        .onAppear {
            Task {
                let s = await model.persistence.loadSettings()
                if !s.onboardingCompleted { showOnboarding = true }
            }
        }
        .overlay(alignment: .top) {
            if let activeSOS = model.sosService.activeSOS {
                ActiveSOSBanner(packet: activeSOS)
                    .padding(.top, 6)
            }
        }
    }
}

struct ActiveSOSBanner: View {
    let packet: SOSPacket
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.octagon.fill")
                .foregroundStyle(.white)
            VStack(alignment: .leading, spacing: 2) {
                Text("Active SOS: \(packet.category.label)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text("Relaying via mesh...")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(ResilixTheme.emergencyRed)
        .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusMedium))
        .padding(.horizontal, ResilixTheme.space16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Active SOS \(packet.category.label) \(packet.severity.label)")
    }
}


