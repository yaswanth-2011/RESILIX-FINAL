// xcode: set sdk=iOS

import SwiftUI

// Cinematic launch: black → cyan seed point → nodes → connections → logo fade/zoom (~2s).
@main
struct ResilixApp: App {
    @StateObject private var appModel = ResilixAppModel()
    @AppStorage("appearance") private var appearance: String = "Dark"
    @AppStorage("isAuthenticated") private var isAuthenticated = false

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
            .environment(\.locale, appModel.localization.locale)
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
    lazy var transferService = TransferService(meshController: meshController)
    lazy var messageService: MessageService = MessageService(meshController: meshController,
                                                             transferService: transferService)
    lazy var sosService: SOSService = SOSService(meshController: meshController)
    lazy var resourceService = ResourceService()
    lazy var permissionService = PermissionService()
    lazy var diagnosticsService = DiagnosticsService()
    lazy var profileService = ProfileService()
    lazy var locationService = LocationService()
    lazy var voiceService = VoiceService()
    lazy var mapPackService = MapPackService()
    lazy var aiService = LocalAIService()
    let localization = LocalizationManager.shared

    #if DEBUG
    lazy var demoController: DemoModeController = DemoModeController(meshController: meshController, mock: mockTransport)
    #else
    lazy var demoController: DemoModeController = DemoModeController(meshController: meshController, mock: MockMeshTransport())
    #endif

    lazy var lifecycle = AppLifecycleService()

    @Published var settings = AppSettings()
    @Published var nodeID: String = ""
    @Published var isMeshRunning = false

    private var locationTask: Task<Void, Never>?

    init() {
        Task { @MainActor in
            await bootstrap()
        }
    }

    /// Loads the persisted state and starts the mesh.
    private func bootstrap() async {
        settings = await persistence.loadSettings()
        nodeID = await loadOrCreateNodeID()

        // The identity lives in the keychain and is created once per device.
        let security = SecurityManager()
        try? await security.setupIdentityIfNeeded(nodeID: nodeID)

        // Interface language.
        localization.apply(settings.language)

        // Profile.
        await profileService.load(settings: settings)

        // Mesh identity.
        let hello = await makeHello()
        await meshController.configure(nodeID: nodeID,
                                        alias: settings.displayName,
                                        hello: hello)
        wireMeshCallbacks()

        // Configure lifecycle
        lifecycle.configure(meshController: meshController, relayManager: relayManager)
        lifecycle.onLaunch()

        await meshController.start()
        isMeshRunning = true

        // Location sharing (only when the user enabled it).
        startLocationSharingIfEnabled()

        // Offline map packs and AI models.
        await mapPackService.load()
        await aiService.load()
        if let modelID = settings.selectedAIModelID {
            await aiService.select(modelID: modelID)
        }

        #if DEBUG
        if settings.isDemoMode {
            await demoController.startDemo()
        }
        #endif
    }

    /// Shares the own position with the mesh when the user allowed it.
    private func startLocationSharingIfEnabled() {
        locationTask?.cancel()
        guard settings.locationSharingEnabled else {
            locationService.stopUpdates()
            return
        }
        locationService.requestPermission()
        locationService.startUpdates()
        var lastLatitude: Double?
        var lastLongitude: Double?
        locationTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 15_000_000_000)
                guard let coordinate = locationService.coordinate else { continue }
                let changed = lastLatitude.map { abs($0 - coordinate.latitude) > 0.0005 } ?? true
                guard changed else { continue }
                lastLatitude = coordinate.latitude
                lastLongitude = coordinate.longitude
                await meshController.broadcastLocation(latitude: coordinate.latitude,
                                                       longitude: coordinate.longitude)
            }
        }
    }

    /// Builds the handshake payload that identifies this node.
    private func makeHello() async -> PeerHello {
        let security = SecurityManager()
        let agreement = (try? await security.agreementPublicKey()) ?? Data()
        let signing = (try? await security.signingPublicKey()) ?? Data()
        return PeerHello(nodeID: nodeID,
                         alias: settings.displayName,
                         agreementPublicKey: agreement,
                         signingPublicKey: signing,
                         supportsRelay: settings.relayEnabled,
                         protocolVersion: ResilixConstants.protocolVersion)
    }

    /// Connects the mesh controller with the application services.
    private func wireMeshCallbacks() {
        meshController.onPacketReceived = { [weak self] delivered in
            guard let self else { return }
            Task { @MainActor in
                await self.route(delivered)
            }
        }
        meshController.onDeliveryUpdate = { [weak self] packetID, state in
            guard let self else { return }
            Task { @MainActor in
                await self.messageService.updateDelivery(packetID: packetID, state: state)
            }
        }
        // Only chat, media and SOS packets are forwarded by this device.
        meshController.relayDecision = { packet in
            switch packet.type {
            case .chat, .mediaChunk, .mediaControl, .sos:
                return true
            case .acknowledgement, .routeAdvertisement, .capabilityAdvertisement,
                 .healthCheck, .resourceReport:
                return false
            }
        }
    }

    /// Distributes a decrypted packet to the service that understands it.
    private func route(_ delivered: DeliveredPayload) async {
        switch delivered.packet.type {
        case .chat:
            await messageService.handleIncoming(delivered)
        case .mediaChunk:
            guard let chunk = TransferService.parseChunk(delivered.plaintext) else { return }
            await transferService.handleChunk(transferID: chunk.transferID,
                                              index: chunk.index,
                                              chunk: chunk.chunk)
        case .mediaControl:
            guard let control = try? JSONDecoder().decode(MediaTransferControl.self,
                                                          from: delivered.plaintext) else { return }
            await transferService.handle(control: control, from: delivered.originNodeID)
        case .sos:
            await sosService.handleIncoming(delivered)
        default:
            break
        }
    }

    /// Stores the settings and keeps the mesh identity in sync.
    func updateSettings(_ change: (inout AppSettings) -> Void) async {
        change(&settings)
        try? await persistence.saveSettings(settings)
        if settings.language != localization.currentLanguageName {
            localization.apply(settings.language)
        }
        if settings.locationSharingEnabled != (locationTask != nil) {
            startLocationSharingIfEnabled()
        }
        if settings.displayName != meshController.localAlias {
            let hello = await makeHello()
            await meshController.configure(nodeID: nodeID,
                                            alias: settings.displayName,
                                            hello: hello)
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
