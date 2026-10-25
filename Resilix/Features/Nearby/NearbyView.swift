import SwiftUI
import MapKit
import CoreLocation

// Nearby liquid glass low opacity — less whiter, only for this section

// MARK: - Nearby Device (UI model with vibrant colors)
struct NearbyDevice: Identifiable {
    let id: String
    let name: String
    let distance: String
    let hopType: HopType
    let signalPercent: Int
    let isRelay: Bool
    let accentGradient: LinearGradient

    enum HopType: String {
        case direct = "Direct"
        case oneHop = "1 Hop"
        case twoHops = "2 Hops"

        var badgeColor: Color {
            switch self {
            case .direct: return Color(hex: "14B8A6") // teal
            case .oneHop: return Color(hex: "3B82F6") // blue
            case .twoHops: return Color(hex: "8B5CF6") // purple
            }
        }
    }

    init(node: MeshNode, distance: String = "120m", hopType: HopType = .direct, signalPercent: Int = 95) {
        self.id = node.id
        self.name = node.alias
        self.distance = distance
        self.hopType = hopType
        self.signalPercent = signalPercent
        self.isRelay = node.isRelay
        self.accentGradient = AvatarView.gradient(for: node.alias)
    }

    init(name: String, distance: String, hopType: HopType, signalPercent: Int, isRelay: Bool = false) {
        self.id = UUID().uuidString
        self.name = name
        self.distance = distance
        self.hopType = hopType
        self.signalPercent = signalPercent
        self.isRelay = isRelay
        self.accentGradient = AvatarView.gradient(for: name)
    }
}

// MARK: - Nearby View (iOS-unique glass, MapKit mini-map, pulse)
struct NearbyView: View {
    @EnvironmentObject var app: ResilixAppModel
    @State private var devices: [NearbyDevice] = []
    @State private var scanState: ScanState = .idle
    @State private var pulsePhase: CGFloat = 0
    @State private var hasAppeared = false
    @Namespace private var scanNamespace
    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
            span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
        )
    )
    private let userCoordinate = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)
    @State private var deviceCoordinates: [CLLocationCoordinate2D] = []

    enum ScanState { case idle, scanning, complete }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        headerSection
                            .padding(.top, 8)

                        scanButtonSection
                            .padding(.top, 20)

                        if scanState == .scanning {
                            miniMapSection
                                .padding(.top, 14)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.7, anchor: .top)
                                        .combined(with: .opacity),
                                    removal: .opacity.combined(with: .scale(scale: 0.9, anchor: .top))
                                ))
                                .matchedGeometryEffect(id: "scanBtn", in: scanNamespace)
                        }

                        if scanState == .scanning {
                            scanningHint
                                .padding(.top, 14)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        if !devices.isEmpty {
                            deviceListSection
                                .padding(.top, 18)
                                .transition(.asymmetric(
                                    insertion: .move(edge: .bottom).combined(with: .opacity),
                                    removal: .move(edge: .bottom).combined(with: .opacity)
                                ))
                        } else if scanState == .idle {
                            emptyState
                                .padding(.top, 40)
                                .transition(.opacity)
                        }
                    }
                    .padding(.bottom, 100)
                }
                .animation(.spring(response: 0.45, dampingFraction: 0.88), value: scanState)
                .animation(.spring(response: 0.4, dampingFraction: 0.9), value: devices.count)
            }
            .background(Color.black)
            .navigationBarHidden(true)
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true
                    loadDemoDevices()
                }
            }
        }
    }

    // MARK: - Header (Resilix font, theme colors)
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L("Nearby"))
                .font(ResilixTheme.font(32, .bold))
                .foregroundStyle(.white)
            Text(L("Devices within mesh range"))
                .font(ResilixTheme.font(15, .regular))
                .foregroundStyle(Color.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
    }

    // MARK: - Scan Button (liquid glass native, three states)
    private var scanButtonSection: some View {
        Group {
            switch scanState {
            case .idle:
                Button { startScan() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 16, weight: .semibold))
                        Text(L("Scan for Devices"))
                            .font(ResilixTheme.font(16, .semibold))
                    }
                    .foregroundStyle(ResilixTheme.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [ResilixTheme.brandCyan, ResilixTheme.brandTeal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .nearbyGlassRounded(cornerRadius: 16, interactive: true)
                    .shadow(color: ResilixTheme.cyanGlowStrong, radius: 16, y: 6)
                }
                .buttonStyle(.plain)
                .matchedGeometryEffect(id: "scanBtn", in: scanNamespace)

            case .scanning:
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(ResilixTheme.brandCyan)
                    Text(L("Scanning for Resilix devices..."))
                        .font(ResilixTheme.font(15, .semibold))
                }
                .foregroundStyle(ResilixTheme.brandCyan)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(ResilixTheme.brandCyan.opacity(0.25), lineWidth: 1)
                        )
                )
                .nearbyGlassRounded(cornerRadius: 16, interactive: false)

            case .complete:
                Button { startScan() } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 16, weight: .semibold))
                        Text("\(devices.count) " + L("ui.devices.found") + " – " + L("ui.scan.again"))
                            .font(ResilixTheme.font(16, .semibold))
                    }
                    .foregroundStyle(ResilixTheme.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        LinearGradient(
                            colors: [ResilixTheme.brandCyan, ResilixTheme.brandTeal],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .nearbyGlassRounded(cornerRadius: 16, interactive: true)
                    .shadow(color: ResilixTheme.cyanGlowStrong, radius: 14, y: 6)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 20)
    }

    // MARK: - Mini Map (Apple MapKit, iPhone center, pulse, Find My-style device images)
    private var miniMapSection: some View {
        ZStack {
            // Real Apple Map — no box behind, map fills the area
            Map(position: $mapPosition) {
                // User iPhone — Find My style device image (iPhone)
                Annotation("", coordinate: userCoordinate) {
                    Image(systemName: "iphone.circle.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(.white, ResilixTheme.brandCyan)
                        .padding(3)
                        .background(Circle().fill(Color.black.opacity(0.25)))
                }

                // Other devices — Find My style phone/device images
                ForEach(Array(deviceCoordinates.enumerated()), id: \.offset) { idx, coord in
                    Annotation("", coordinate: coord) {
                        let isRelay = devices[safe: idx]?.isRelay ?? (idx == 2)
                        Image(systemName: devicePinImage(isRelay: isRelay, idx: idx))
                            .font(.system(size: 28))
                            .foregroundStyle(.white, ResilixTheme.brandCyan)
                            .padding(2)
                            .background(Circle().fill(Color.black.opacity(0.25)))
                            .opacity(pulsePhase > 0.25 ? 1 : 0)
                            .scaleEffect(pulsePhase > 0.25 ? 1 : 0.6)
                            .animation(.spring(response: 0.4, dampingFraction: 0.75).delay(Double(idx) * 0.08 + 0.4), value: pulsePhase)
                    }
                }
            }
            .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .allowsHitTesting(false)
            .colorScheme(.dark)

            // Pulsing rings emanating from iPhone center
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(ResilixTheme.brandCyan.opacity(0.28 - Double(i) * 0.07), lineWidth: 1.4)
                    .frame(width: 50 + CGFloat(i) * 36 + pulsePhase * 150,
                           height: 50 + CGFloat(i) * 36 + pulsePhase * 150)
                    .opacity(1.0 - pulsePhase * 0.75)
            }
        }
        .frame(height: 440)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 20)
    }

    private func devicePinImage(isRelay: Bool, idx: Int) -> String {
        if isRelay {
            return "laptopcomputer.circle.fill"
        }
        let phoneIcons = [
            "iphone.circle.fill",
            "iphone.gen2.circle.fill",
            "iphone.gen1.circle.fill",
            "ipad.circle.fill",
            "iphone.gen3.circle.fill",
        ]
        return phoneIcons[idx % phoneIcons.count]
    }

    private var scanningHint: some View {
        Text(L("Scanning for nearby Resilix devices..."))
            .font(ResilixTheme.font(13, .medium))
            .foregroundStyle(Color.white.opacity(0.45))
            .frame(maxWidth: .infinity)
    }

    // MARK: - Device List — cards come up from bottom with stagger after scan
    private var deviceListSection: some View {
        VStack(spacing: 12) {
            ForEach(Array(devices.enumerated()), id: \.element.id) { idx, device in
                NearbyDeviceCard(device: device) {
                    // Open chat — future: navigate to MessageThreadView
                }
                .transition(.asymmetric(
                    insertion: .move(edge: .bottom).combined(with: .opacity),
                    removal: .move(edge: .bottom).combined(with: .opacity)
                ))
                .animation(.spring(response: 0.48, dampingFraction: 0.88).delay(Double(idx) * 0.06), value: devices.count)
            }
        }
        .padding(.horizontal, 20)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.white.opacity(0.06)).frame(width: 88, height: 88)
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(ResilixTheme.textTertiary)
            }
            Text(L("No nearby devices"))
                .font(ResilixTheme.font(15, .semibold))
                .foregroundStyle(.white)
            Text(L("Tap Scan to discover Resilix devices around you."))
                .font(ResilixTheme.font(12, .regular))
                .foregroundStyle(Color.white.opacity(0.5))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    // MARK: - Actions — choreographed: cards bottom, map from button, pulse, pins pop, cards up from bottom
    private func startScan() {
        // Stage 1: cards go to bottom, button becomes scanning, map will expand from button
        withAnimation(.spring(response: 0.44, dampingFraction: 0.86)) {
            scanState = .scanning
            devices = [] // removal to bottom via transition
            pulsePhase = 0
            deviceCoordinates = []
        }
        // Stage 2: slightly delayed — map is now visible, generate pins and start pulsing/scan animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            generateDeviceCoordinates()
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: false)) {
                pulsePhase = 1.0
            }
        }
        // Stage 3: after scan (3–4s), devices pop and cards come up from bottom, map fades
        Task {
            try? await Task.sleep(nanoseconds: 3_600_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.52, dampingFraction: 0.85)) {
                    loadDemoDevices() // insertion from bottom
                    scanState = .complete
                }
                withAnimation(.easeOut(duration: 0.35)) {
                    pulsePhase = 0
                }
            }
        }
    }

    /// The pins are placed on the positions the peers really shared.
    private func generateDeviceCoordinates() {
        var coords: [CLLocationCoordinate2D] = []
        for node in app.meshController.peers {
            guard let latitude = node.latitude, let longitude = node.longitude else { continue }
            coords.append(CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
        deviceCoordinates = coords
    }

    private func devicePinColor(for idx: Int) -> Color {
        let palette: [Color] = [
            Color(hex: "6B8296"), Color(hex: "7A8FA3"), Color(hex: "6B9A8F"),
            Color(hex: "9E8C7A"), Color(hex: "8B7F9A"), Color(hex: "6E8C9B"),
        ]
        return palette[idx % palette.count]
    }

    /// Fills the list with the peers that were really discovered.
    ///
    /// The distance is only shown when the peer shared its position, the
    /// signal value comes from the link quality of the transport.
    private func loadDemoDevices() {
        if app.demoController.isDemoMode {
            devices = [
                NearbyDevice(name: "Sarah K.", distance: "120m", hopType: .direct, signalPercent: 95),
                NearbyDevice(name: "Marcus D.", distance: "340m", hopType: .oneHop, signalPercent: 72),
                NearbyDevice(name: "ResBot-a", distance: "510m", hopType: .oneHop, signalPercent: 63, isRelay: true),
                NearbyDevice(name: "James R.", distance: "780m", hopType: .twoHops, signalPercent: 44),
                NearbyDevice(name: "Emma T.", distance: "1.1km", hopType: .twoHops, signalPercent: 38),
            ]
            return
        }

        let nodes = app.meshController.peers
        devices = nodes.prefix(6).map { node in
            let connected = app.meshController.isConnected(to: node.id)
            let route = app.meshController.routing.routes.first { $0.destination == node.id }
            let hops = route?.hopCount ?? 1
            let hopType: NearbyDevice.HopType
            if connected || hops <= 1 {
                hopType = .direct
            } else if hops == 2 {
                hopType = .oneHop
            } else {
                hopType = .twoHops
            }
            var distance = "—"
            if let latitude = node.latitude, let longitude = node.longitude {
                let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                distance = app.locationService.formattedDistance(to: coordinate) ?? "—"
            }
            return NearbyDevice(node: node,
                                distance: distance,
                                hopType: hopType,
                                signalPercent: app.meshController.signalStrength(for: node.id) ?? 0)
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let h: [CGFloat] = [5, 8, 11, 14]
        return h[index]
    }

    private func barColor(for index: Int) -> Color {
        if index < filledCount { return Color.white.opacity(0.9) }
        return Color.white.opacity(0.18)
    }
}

// MARK: - Nearby Low-Opacity Liquid Glass (even less whiter, only for Nearby)
private extension View {
    @ViewBuilder
    func nearbyGlassRounded(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
        if #available(iOS 26.0, *) {
            self.modifier(NearbyLowGlassModifier(shape: .rounded(cornerRadius), interactive: interactive))
        } else {
            self
                .background(Color.white.opacity(0.012))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.035), lineWidth: 0.5)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.02), lineWidth: 0.3)
                        .blendMode(.overlay)
                )
                .shadow(color: Color.black.opacity(0.10), radius: 3, x: 0, y: 1)
        }
    }

    @ViewBuilder
    func nearbyGlassCapsule(interactive: Bool = true) -> some View {
        if #available(iOS 26.0, *) {
            self.modifier(NearbyLowGlassModifier(shape: .capsule, interactive: interactive))
        } else {
            self
                .background(Color.white.opacity(0.012))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.white.opacity(0.04), lineWidth: 0.5))
                .overlay(Capsule().stroke(Color.white.opacity(0.02), lineWidth: 0.3).blendMode(.overlay))
                .shadow(color: Color.black.opacity(0.10), radius: 3, x: 0, y: 1)
        }
    }
}

@available(iOS 26.0, *)
private struct NearbyLowGlassModifier: ViewModifier {
    enum Shape { case capsule, rounded(CGFloat) }
    let shape: Shape
    let interactive: Bool
    func body(content: Content) -> some View {
        let glass = interactive ? Glass.regular.interactive() : Glass.regular
        // Extra low tint — less whiter than previous 0.012
        let tint: CGFloat = 0.006
        switch shape {
        case .capsule:
            content.glassEffect(glass.tint(Color.white.opacity(tint)), in: Capsule())
        case .rounded(let r):
            content.glassEffect(glass.tint(Color.white.opacity(tint)), in: RoundedRectangle(cornerRadius: r, style: .continuous))
        }
    }
}
