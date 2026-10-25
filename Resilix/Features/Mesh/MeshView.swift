import SwiftUI
import MapKit
import CoreLocation
import Foundation

// MARK: - Mesh color tokens
// Bright, visibly distinct colors for each role / stat.
private enum MeshColors {
    static let you      = Color(hex: "22D3EE")   // vivid cyan
    static let direct   = Color(hex: "22E36A")   // vivid green
    static let relay    = Color(hex: "FB923C")   // vivid orange
    static let multiHop = Color(hex: "A78BFA")   // vivid violet
    /// Distinct color for the "Routes" stat (network paths info)
    static let routes   = Color(hex: "F472B6")   // vivid pink

    static func pin(for hop: MeshPeer.HopType) -> Color {
        switch hop {
        case .direct:    return direct
        case .relay:     return relay
        case .multiHop:  return multiHop
        }
    }
}

// MARK: - Mesh UI model — same data as the network diagram
struct MeshPeer: Identifiable {
    let id: String
    let name: String
    let hopType: HopType
    let signalPercent: Int
    let isRelay: Bool
    let distance: String
    let connectionLabel: String
    let accentColor: Color
    /// Position the peer shared with the mesh (nil when it did not share one).
    let coordinate: CLLocationCoordinate2D?

    enum HopType: String {
        case direct = "Direct"
        case relay = "Relay"
        case multiHop = "2+ Hop"
    }
}

// MARK: - Mesh Network View
struct MeshView: View {
    @EnvironmentObject var app: ResilixAppModel
    @State private var peers: [MeshPeer] = []
    @State private var selectedPeer: MeshPeer?
    @State private var autoRoute: Bool = true
    @State private var relayEnabled: Bool = false
    @State private var pulse: Bool = false
    @State private var hasAppeared: Bool = false
    @State private var showDiagnostics: Bool = false
    @State private var testMessage: String?
    /// The device's real position (`nil` until the first GPS fix).
    @State private var userCoordinate: CLLocationCoordinate2D? = nil

    var body: some View {
        NavigationStack {
            ZStack {
                ResilixTheme.backgroundPrimary
                    .ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: ResilixTheme.space20) {
                        headerSection
                            .padding(.top, ResilixTheme.space8)

                        networkMapCard

                        statsRow

                        actionCards

                        Spacer(minLength: ResilixTheme.space24)
                    }
                    .padding(.bottom, 100)
                }
            }
            .navigationBarHidden(true)
            .task { await loadPeers() }
            .onReceive(app.meshController.$peers) { _ in
                Task { await loadPeers() }
            }
            .alert(L("Mesh"), isPresented: .constant(testMessage != nil), presenting: testMessage) { _ in
                Button(L("OK")) { testMessage = nil }
            } message: { message in
                Text(message)
            }
            .sheet(isPresented: $showDiagnostics) {
                DiagnosticsView()
                    .presentationDetents([.medium, .large])
                    .presentationBackground(ResilixTheme.backgroundPrimary)
            }
            .onAppear {
                if !hasAppeared {
                    hasAppeared = true
                    withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                        pulse = true
                    }
                    startLocationUpdates()
                }
            }
            .onChange(of: app.locationService.coordinate) { _, newCoordinate in
                if let newCoordinate { userCoordinate = newCoordinate }
            }
            .sheet(item: $selectedPeer) { peer in
                MeshDeviceDetailSheet(peer: peer)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(ResilixTheme.backgroundPrimary)
            }
        }
    }

    // MARK: - Header
    private var headerSection: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text(L("Mesh Network"))
                    .font(ResilixTheme.font(32, .bold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(ResilixTheme.successGreen)
                            .frame(width: 7, height: 7)
                            .scaleEffect(pulse ? 1.25 : 0.85)
                        Text(L("Healthy"))
                            .font(ResilixTheme.font(13, .semibold))
                            .foregroundStyle(ResilixTheme.successGreen)
                    }
                    Text("· \(peers.count) " + L("ui.devices") + " · \(app.meshController.connectedPeerIDs.count) " + L("ui.connections"))
                        .font(ResilixTheme.font(13, .regular))
                        .foregroundStyle(ResilixTheme.textTertiary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                MeshToggleChip(label: L("Auto Route"), isOn: Binding(
                    get: { app.meshController.routing.automaticRoutingEnabled },
                    set: { newValue in app.meshController.routing.automaticRoutingEnabled = newValue }
                ))
                MeshToggleChip(label: L("Relay"), isOn: Binding(
                    get: { app.relayManager.isRelayActive },
                    set: { newValue in Task { await app.relayManager.setRelay(newValue) } }
                ))
            }
        }
        .padding(.horizontal, ResilixTheme.space20)
    }

    // MARK: - Network Map Card (Apple Maps)
    private var networkMapCard: some View {
        MeshAppleMapView(peers: peers, userCoordinate: userCoordinate, pulse: pulse) { peer in
            selectedPeer = peer
        }
        .padding(.horizontal, ResilixTheme.space20)
    }

    // MARK: - Location
    /// Starts real location updates so the mesh map shows the actual position
    /// of this device instead of a fixed placeholder.
    private func startLocationUpdates() {
        if app.locationService.authorization == .notDetermined {
            app.locationService.requestPermission()
        }
        app.locationService.startUpdates()
        if let coordinate = app.locationService.coordinate {
            userCoordinate = coordinate
        }
    }

    // MARK: - Stats Row
    // Each stat number uses a distinct color tied to its meaning so they're
    // visually different at a glance.
    private var statsRow: some View {
        HStack(spacing: 10) {
            MeshStatBox(value: "\(peers.count)", label: L("Members"), color: MeshColors.direct)
            MeshStatBox(value: "\(meshHealth)", label: L("Health"), color: MeshColors.you)
            MeshStatBox(value: "\(app.meshController.routing.routes.count)", label: L("Routes"), color: MeshColors.routes)
            MeshStatBox(value: "\(app.meshController.statistics.relayedPackets)", label: L("Relayed"), color: MeshColors.relay)
        }
        .padding(.horizontal, ResilixTheme.space20)
    }

    // MARK: - Action Cards
    private var actionCards: some View {
        VStack(spacing: 10) {
            MeshActionRow(icon: "viewfinder", title: L("Scan for Devices"), subtitle: L("Discover new mesh peers")) {
                Task { await rescan() }
            }
            MeshActionRow(icon: "waveform.path.ecg", title: L("Network Diagnostics"), subtitle: L("Check routes & latency")) {
                showDiagnostics = true
            }
            MeshActionRow(icon: "paperplane.fill", title: L("Send Test Message"), subtitle: L("Watch packet travel the mesh")) {
                Task { await sendTestMessage() }
            }
        }
        .padding(.horizontal, ResilixTheme.space20)
    }

    // MARK: - Data
    /// Builds the peer list from the real mesh state.
    private func loadPeers() async {
        let nodes = app.meshController.peers
        peers = nodes.map { node in
            let connected = app.meshController.isConnected(to: node.id)
            let route = app.meshController.routing.routes.first { $0.destination == node.id }
            let hopType: MeshPeer.HopType
            if connected {
                hopType = .direct
            } else if node.isRelay {
                hopType = .relay
            } else {
                hopType = .multiHop
            }
            var coordinate: CLLocationCoordinate2D?
            if let latitude = node.latitude, let longitude = node.longitude {
                coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }
            let distance = coordinate.flatMap { app.locationService.formattedDistance(to: $0) } ?? "—"
            let connectionLabel = connected
                ? "Direct"
                : (route.map { "\($0.hopCount) hop" + ($0.hopCount == 1 ? "" : "s") } ?? "Unknown")
            return MeshPeer(id: node.id,
                            name: node.displayName ?? node.alias,
                            hopType: hopType,
                            signalPercent: app.meshController.signalStrength(for: node.id) ?? 0,
                            isRelay: node.isRelay,
                            distance: distance,
                            connectionLabel: connectionLabel,
                            accentColor: MeshColors.pin(for: hopType),
                            coordinate: coordinate)
        }
    }

    /// Health of the local mesh: share of the discovered peers that are
    /// currently connected (0 - 100).
    private var meshHealth: Int {
        guard !peers.isEmpty else { return 0 }
        let connected = app.meshController.connectedPeerIDs.count
        return min(100, Int((Double(connected) / Double(peers.count)) * 100))
    }

    /// Restarts the discovery on every transport.
    private func rescan() async {
        for transport in app.meshController.availableTransports {
            await transport.stopDiscovery()
        }
        for transport in app.meshController.availableTransports {
            await transport.startDiscovery()
        }
        await loadPeers()
    }

    /// Sends a short test packet to every connected peer.
    private func sendTestMessage() async {
        guard !app.meshController.connectedPeerIDs.isEmpty else {
            testMessage = L("No peer is connected yet — scan for devices first.")
            return
        }
        var sent = 0
        for peerID in app.meshController.connectedPeerIDs {
            do {
                _ = try await app.meshController.sendSecurePacket(type: .chat,
                                                                  plaintext: Data(L("Resilix mesh test message").utf8),
                                                                  destination: peerID)
                sent += 1
            } catch {
                continue
            }
        }
        testMessage = sent > 0
            ? String(format: L("Test packet sent to %@ peer(s)."), String(sent))
            : L("The test packet could not be sent.")
    }
}


private struct MeshToggleChip: View {
    let label: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(ResilixTheme.font(11, .semibold))
                .foregroundStyle(ResilixTheme.textSecondary)
                .fixedSize()
            Toggle("", isOn: $isOn.animation(.easeInOut(duration: 0.18)))
                .labelsHidden()
                .tint(ResilixTheme.brandCyan)
                .scaleEffect(0.8)
        }
    }
}

// MARK: - Stat Box
private struct MeshStatBox: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(ResilixTheme.font(24, .heavy))
                .foregroundStyle(color)
            Text(label)
                .font(ResilixTheme.font(11, .medium))
                .foregroundStyle(ResilixTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.018))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.06), lineWidth: 0.6)
                )
        )
        .liquidGlassRounded(cornerRadius: 14, interactive: false)
    }
}

// MARK: - Action Row
private struct MeshActionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(ResilixTheme.brandCyan.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(ResilixTheme.brandCyan)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ResilixTheme.font(16, .semibold))
                        .foregroundStyle(ResilixTheme.textPrimary)
                    Text(subtitle)
                        .font(ResilixTheme.font(12, .regular))
                        .foregroundStyle(ResilixTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(ResilixTheme.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.white.opacity(0.018))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(Color.white.opacity(0.04), lineWidth: 0.6)
                    )
            )
            .liquidGlassRounded(cornerRadius: 18, interactive: true)
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - Apple Maps Network View
struct MeshAppleMapView: View {
    let peers: [MeshPeer]
    let userCoordinate: CLLocationCoordinate2D?
    let pulse: Bool
    let onSelect: (MeshPeer) -> Void

    /// Startup centre until the first real GPS fix arrives.
    private static let fallbackCenter = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)

    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: fallbackCenter,
            span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        )
    )
    /// `true` once the camera has been centred on the first real fix.
    @State private var didCenterOnUser = false

    /// The device itself — shown only once it has a real GPS fix.
    private struct MeshYouMark: Identifiable {
        let id = "you"
        let coordinate: CLLocationCoordinate2D
    }

    /// One dotted connection line from "You" to a peer that shared a position.
    private struct MeshLine: Identifiable {
        let id = UUID()
        let from: CLLocationCoordinate2D
        let to: CLLocationCoordinate2D
        let color: Color
    }

    /// The "You" marker — present only once the phone has a real GPS fix.
    private var youMark: [MeshYouMark] {
        guard let userCoordinate else { return [] }
        return [MeshYouMark(coordinate: userCoordinate)]
    }

    /// Dotted connection lines from the real position to every peer that shared
    /// a position — empty until the first GPS fix.
    private var meshLines: [MeshLine] {
        guard let userCoordinate else { return [] }
        return peers.compactMap { peer in
            guard let coordinate = peer.coordinate else { return nil }
            return MeshLine(from: userCoordinate, to: coordinate,
                            color: lineColor(for: peer.hopType))
        }
    }

    /// Peers that shared a position, together with that position.
    private var pinnedPeers: [(peer: MeshPeer, coordinate: CLLocationCoordinate2D)] {
        peers.compactMap { peer in
            guard let coordinate = peer.coordinate else { return nil }
            return (peer, coordinate)
        }
    }

    private func lineColor(for hop: MeshPeer.HopType) -> Color {
        MeshColors.pin(for: hop)
    }

    var body: some View {
        VStack(spacing: 14) {
            // The map
            ZStack(alignment: .topTrailing) {
                Map(position: $cameraPosition, interactionModes: [.pan, .zoom]) {
                    // "You" center node — only at the real GPS fix.
                    ForEach(youMark) { mark in
                        Annotation("You", coordinate: mark.coordinate) {
                            YouMapPin()
                        }
                    }

                    // Dotted mesh connection lines (You → peer) — only from
                    // the real position, never from a made-up coordinate.
                    ForEach(Array(meshLines.enumerated()), id: \.offset) { _, line in
                        MapPolyline(coordinates: [line.from, line.to])
                            .stroke(
                                line.color.opacity(0.65),
                                style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [5, 4])
                            )
                    }

                    // Peer annotations (only peers that shared a position)
                    ForEach(Array(pinnedPeers.enumerated()), id: \.offset) { _, item in
                        Annotation(item.peer.name, coordinate: item.coordinate) {
                            PeerMapPin(peer: item.peer, pulse: pulse)
                                .onTapGesture {
                                    onSelect(item.peer)
                                }
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
                .colorScheme(.dark)
                .allowsHitTesting(true)
                .accessibilityLabel(L("mesh.map.description") + " \(peers.count) " + L("ui.devices"))
            }
            .frame(height: 360)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.05), lineWidth: 0.6)
            )
            .liquidGlassRounded(cornerRadius: 22, interactive: false)

            // Legend
            HStack(spacing: 18) {
                MeshLegendItem(color: MeshColors.you, label: L("You"))
                MeshLegendItem(color: MeshColors.direct, label: L("Direct"))
                MeshLegendItem(color: MeshColors.relay, label: L("Relay"))
                MeshLegendItem(color: MeshColors.multiHop, label: L("2+ Hop"))
            }
            .frame(maxWidth: .infinity)
            // Centre on the first real GPS fix, then leave the map alone so
            // the user can pan.
            .onChange(of: userCoordinate) { _, newCoordinate in
                guard let newCoordinate, !didCenterOnUser else { return }
                didCenterOnUser = true
                withAnimation(.easeInOut(duration: 0.35)) {
                    cameraPosition = .camera(MapCamera(
                        centerCoordinate: newCoordinate,
                        distance: 3000,
                        heading: 0,
                        pitch: 0
                    ))
                }
            }
        }
    }
}

// MARK: - "You" center pin (Apple Maps iPhone glyph)
private struct YouMapPin: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Pulsing halo behind the iPhone glyph (Find My style)
            Circle()
                .fill(MeshColors.you.opacity(0.20))
                .frame(width: 56, height: 56)
                .scaleEffect(pulse ? 1.15 : 0.9)
                .opacity(pulse ? 0.4 : 0.85)
            // iPhone glyph — white face, your-color body, matches Find My
            Image(systemName: "iphone.circle.fill")
                .font(.system(size: 38))
                .foregroundStyle(.white, MeshColors.you)
                .shadow(color: ResilixTheme.cyanGlowStrong, radius: 6)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityLabel(Text(L("Your device")))
    }
}

// MARK: - Peer pin (Apple Maps iPhone glyph)
private struct PeerMapPin: View {
    let peer: MeshPeer
    let pulse: Bool

    private var pinColor: Color {
        MeshColors.pin(for: peer.hopType)
    }

    // Find My style: iPhone glyph for normal peers, laptop for relays.
    private var pinIcon: String {
        if peer.isRelay { return "laptopcomputer.circle.fill" }
        switch peer.hopType {
        case .direct:    return "iphone.circle.fill"
        case .relay:     return "laptopcomputer.circle.fill"
        case .multiHop:  return "iphone.gen2.circle.fill"
        }
    }

    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: pinIcon)
                .font(.system(size: 30))
                .foregroundStyle(.white, pinColor)
                .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
                .scaleEffect(pulse ? 1.06 : 1.0)
            Text(peer.name)
                .font(ResilixTheme.font(10, .semibold))
                .foregroundStyle(ResilixTheme.textPrimary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(
                    Capsule()
                        .fill(Color.black.opacity(0.55))
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(peer.name), \(peer.connectionLabel), \(peer.signalPercent) " + L("ui.percent.signal"))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Legend
private struct MeshLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(ResilixTheme.font(11, .medium))
                .foregroundStyle(ResilixTheme.textSecondary)
        }
    }
}

// MARK: - Device Detail Sheet (Marcus D. style)
struct MeshDeviceDetailSheet: View {
    let peer: MeshPeer
    @Environment(\.dismiss) private var dismiss

    private var initials: String {
        let parts = peer.name.split(separator: " ").filter { $0 != "&" }
        let first = parts.first?.first.map(String.init) ?? "?"
        let second = parts.count > 1 ? parts[1].first.map(String.init) ?? "" : ""
        return (first + second).uppercased()
    }

    private var hopCount: String {
        switch peer.hopType {
        case .direct: return L("1 hop")
        case .relay: return L("1 hop")
        case .multiHop: return L("2 hops")
        }
    }

    private var relayLabel: String {
        peer.isRelay ? "Active" : "Limited"
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer(minLength: 4)
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(AvatarView.gradient(for: peer.name))
                            .frame(width: 56, height: 56)
                            .shadow(color: AvatarView.color(for: peer.name).opacity(0.45), radius: 8, y: 2)
                        Text(initials)
                            .font(ResilixTheme.font(20, .bold))
                            .foregroundStyle(.white)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(peer.name)
                            .font(ResilixTheme.font(24, .bold))
                            .foregroundStyle(ResilixTheme.textPrimary)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(ResilixTheme.successGreen)
                                .frame(width: 7, height: 7)
                            Text(L("Connected"))
                                .font(ResilixTheme.font(13, .semibold))
                                .foregroundStyle(ResilixTheme.successGreen)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, ResilixTheme.space20)

                // Stats
                HStack(spacing: 10) {
                    MeshDetailStat(value: hopCount, label: L("Hop Count"))
                    MeshDetailStat(value: "\(peer.signalPercent)", label: L("Signal"))
                    MeshDetailStat(value: relayLabel, label: L("Relay"))
                }
                .padding(.horizontal, ResilixTheme.space20)

                // Buttons
                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text(L("Message"))
                            .font(ResilixTheme.font(15, .heavy))
                            .tracking(0.6)
                            .foregroundStyle(ResilixTheme.textOnAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                LinearGradient(
                                    colors: [ResilixTheme.brandCyan, ResilixTheme.brandTeal],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .liquidGlassRounded(cornerRadius: 16, interactive: true)
                            .shadow(color: ResilixTheme.cyanGlowStrong, radius: 10, y: 4)
                    }
                    .buttonStyle(PressScaleStyle())

                    Button {
                        dismiss()
                    } label: {
                        Text(L("View Route"))
                            .font(ResilixTheme.font(15, .heavy))
                            .tracking(0.6)
                            .foregroundStyle(ResilixTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.025))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.white.opacity(0.05), lineWidth: 0.7)
                                    )
                            )
                            .liquidGlassRounded(cornerRadius: 16, interactive: true)
                    }
                    .buttonStyle(PressScaleStyle())
                }
                .padding(.horizontal, ResilixTheme.space20)
                .padding(.top, 4)
            }
            .padding(.vertical, ResilixTheme.space20)
        }
        .background(ResilixTheme.backgroundPrimary)
    }
}

// MARK: - Detail Stat (used inside the sheet)
private struct MeshDetailStat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(ResilixTheme.font(18, .bold))
                .foregroundStyle(ResilixTheme.textPrimary)
            Text(label)
                .font(ResilixTheme.font(11, .medium))
                .foregroundStyle(ResilixTheme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.018))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.04), lineWidth: 0.6)
                )
        )
        .liquidGlassRounded(cornerRadius: 14, interactive: false)
    }
}

// MARK: - Previews
struct MeshView_Previews: PreviewProvider {
    static var previews: some View {
        MeshView().environmentObject(ResilixAppModel())
    }
}
