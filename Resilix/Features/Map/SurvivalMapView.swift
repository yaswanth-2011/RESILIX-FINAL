import SwiftUI
import MapKit

// MARK: - Map color tokens
// Distinct color per role, so You / Direct / Relay / Shelter / Route are all
// visually different at a glance. Uses only theme tokens.
private enum MapColors {
    static let you      = ResilixTheme.brandCyan
    static let direct   = ResilixTheme.brandBlueGray
    static let relay    = ResilixTheme.brandAmber
    static let shelter  = ResilixTheme.emergencyRed
    static let route    = ResilixTheme.brandSlate
    /// Brighter, more vivid green for the "GPS Active" status indicator
    /// (more saturated than the muted `successGreen` theme token).
    static let gpsGreen = Color(hex: "22E36A")
}

// MARK: - Map style options (Layers sheet)
enum MapStyleOption: String, CaseIterable, Identifiable {
    case standard  = "Standard"
    case hybrid    = "Hybrid"
    case satellite = "Satellite"
    case muted     = "Muted"
    case transit   = "Transit"
    case threeD    = "3D"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .standard:  return "map.fill"
        case .hybrid:    return "globe.americas.fill"
        case .satellite: return "globe"
        case .muted:     return "map"
        case .transit:   return "tram.fill"
        case .threeD:    return "square.3.layers.3d"
        }
    }

    var subtitle: String {
        switch self {
        case .standard:  return "Apple Maps standard view"
        case .hybrid:    return "Satellite imagery with roads & labels"
        case .satellite: return "Pure satellite imagery"
        case .muted:     return "Soft, low-saturation map for overview"
        case .transit:   return "Map highlighting public transport"
        case .threeD:    return "Realistic 3D buildings & terrain"
        }
    }
}

// MARK: - Demo map peer (used for the offline map view)
struct MapPeer: Identifiable {
    let id: String
    let name: String
    let kind: Kind
    let coordinate: CLLocationCoordinate2D

    enum Kind { case direct, relay, shelter }
}

// MARK: - Offline Map
struct SurvivalMapView: View {
    @EnvironmentObject var app: ResilixAppModel
    @State private var selected: MapPeer?
    @State private var showLayers = false
    @State private var filter: MapFilter = .all
    @State private var styleOption: MapStyleOption = .threeD
    @State private var pitch3D: Double = 55          // 0–75° tilt
    @State private var show3DPopup = false           // long-press 3D → popup
    @State private var showOfflineMaps = false        // offline map packs
    @State private var threeDMode: ThreeDMode = .tilted
    @State private var dashPhase: CGFloat = 0        // animates mesh connection lines

    /// 3D mode options shown in the long-press popup.
    enum ThreeDMode: String, CaseIterable, Identifiable {
        case off       = "Off"
        case tilted    = "Tilted"
        case cinematic = "Cinematic"
        var id: String { rawValue }

        var subtitle: String {
            switch self {
            case .off:       return "Flat top-down map"
            case .tilted:    return "Subtle tilt for context"
            case .cinematic: return "Deep 3D with rotation"
            }
        }

        var defaultPitch: Double {
            switch self {
            case .off:       return 0
            case .tilted:    return 30
            case .cinematic: return 65
            }
        }
    }
    @State private var searchText: String = ""
    @FocusState private var searchFocused: Bool
    @State private var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
            span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        )
    )

    // Live 2-finger gesture state (drag adjusts pitch, pinch adjusts distance)
    @GestureState private var gesturePitchDelta: Double = 0
    @GestureState private var gestureDistanceScale: CGFloat = 1

    private let userCoordinate = CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090)

    enum MapFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case devices = "Devices"
        case shelters = "Shelters"
        case routes = "Routes"
        var id: String { rawValue }
    }

    private var is3D: Bool { styleOption == .threeD }

    /// 3D pitch is available in every map style — the user can tilt the
    /// camera in any of them, controlled by `pitch3D` (0–75°).
    private var wants3DCamera: Bool { true }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                // Apple Maps, light mode, with 3D pitch. The map uses
                // `safeAreaInset` to make room for the top section and the
                // bottom slider, so the top section can sit at the very top
                // (just below the status bar) and the slider sits at a
                // consistent position above the tab bar.
                Map(position: $cameraPosition, interactionModes: [.pan, .zoom, .rotate, .pitch]) {
                    Annotation("You", coordinate: userCoordinate, anchor: .bottom) {
                        YouMapAnnotation()
                    }

                    // Halo polylines — soft white underlay so the line pops
                    // off any map style (satellite, standard, hybrid…).
                    ForEach(visiblePeers) { peer in
                        MapPolyline(coordinates: [userCoordinate, peer.coordinate])
                            .stroke(
                                Color.white.opacity(0.45),
                                style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round)
                            )
                    }

                    // Core polylines — bold colored marching dashes flowing
                    // from "You" out to each peer.
                    ForEach(visiblePeers) { peer in
                        MapPolyline(coordinates: [userCoordinate, peer.coordinate])
                            .stroke(
                                color(for: peer.kind),
                                style: StrokeStyle(
                                    lineWidth: 3.5,
                                    lineCap: .round,
                                    lineJoin: .round,
                                    miterLimit: 0,
                                    dash: [6, 4],
                                    dashPhase: dashPhase
                                )
                            )
                    }

                    ForEach(visiblePeers) { peer in
                        Annotation(peer.name, coordinate: peer.coordinate, anchor: .bottom) {
                            Button {
                                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                                    selected = peer
                                }
                            } label: {
                                PeerMapAnnotation(peer: peer)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .mapStyle(mapStyle(for: styleOption))
                .colorScheme(.light)
                .mapControls {
                    MapScaleView()
                }
                .ignoresSafeArea(edges: .horizontal)
                // 2-finger gesture: drag up/down to adjust pitch (3D-ness),
                // pinch to zoom in/out (distance).
                .gesture(threeDGesture)
                .onAppear { apply3DCameraIfNeeded() }
                .onChange(of: styleOption) { _, _ in apply3DCameraIfNeeded() }
                .onChange(of: threeDMode) { _, _ in apply3DCameraIfNeeded() }
                .onChange(of: pitch3D) { _, _ in apply3DCameraIfNeeded() }
                // Animate the marching dashes on the mesh connection lines.
                // dash period = on + off = 6 + 4 = 10; animate 0 → -10.
                .task {
                    await animateDashPhase()
                }
                // Top inset — pushes the map content down so the top section
                // can sit at the very top of the safe area.
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 10) {
                        topVerticalCard
                        searchBar
                        legendGlass
                    }
                    .padding(.horizontal, ResilixTheme.space16)
                    .padding(.top, ResilixTheme.space8)
                    .padding(.bottom, ResilixTheme.space12)
                }
                // Bottom inset — pushes the map up so the slider sits at a
                // consistent low position above the tab bar.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    nativeSegmentedFilter
                        .padding(.horizontal, ResilixTheme.space16)
                        .padding(.bottom, ResilixTheme.space8)
                        .padding(.top, ResilixTheme.space8)
                }
            }
            .background(ResilixTheme.backgroundPrimary)
            .navigationBarHidden(true)
            .sheet(item: $selected) { peer in
                MapPeerDetailSheet(peer: peer)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(ResilixTheme.backgroundPrimary)
            }
            .sheet(isPresented: $showLayers) {
                MapLayersSheet(styleOption: $styleOption)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(ResilixTheme.backgroundPrimary)
            }
            .sheet(isPresented: $showOfflineMaps) {
                OfflineMapSheet()
                    .environmentObject(app)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(ResilixTheme.backgroundPrimary)
            }
            .sheet(isPresented: $show3DPopup) {
                ThreeDPopupSheet(
                    mode: $threeDMode,
                    pitch: $pitch3D,
                    currentStyle: styleOption
                ) {
                    apply3DCameraIfNeeded()
                }
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(ResilixTheme.backgroundPrimary)
            }
        }
    }

    // MARK: - Top vertical glass card (header only) — same liquid-glass
    // style as the search bar, legend, and slider.
    private var topVerticalCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerOverlay
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
                )
        )
        .liquidGlassRounded(cornerRadius: ResilixTheme.cornerRadiusLarge, interactive: false)
    }

    // MARK: - Header
    private var headerOverlay: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Map")
                    .font(ResilixTheme.font(28, .bold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                HStack(spacing: 6) {
                    Circle()
                        .fill(MapColors.gpsGreen)
                        .frame(width: 7, height: 7)
                    Text("GPS Active")
                        .font(ResilixTheme.font(13, .semibold))
                        .foregroundStyle(MapColors.gpsGreen)
                    Text("· Offline map")
                        .font(ResilixTheme.font(13, .regular))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
            }
            Spacer()
            // Header action row: 4 icon buttons + compass, all the same size
            HStack(spacing: 6) {
                headerIconButton(icon: "square.3.layers.3d", label: "Layers") {
                    showLayers.toggle()
                }
                headerIconButton(icon: "square.and.arrow.down", label: "Offline maps") {
                    showOfflineMaps = true
                }
                threeDHeaderButton
                headerIconButton(icon: "location.fill", label: "Locate") {
                    recenter()
                }
                headerIconButton(icon: "scope", label: "Recenter") {
                    recenter()
                }
                headerIconButton(icon: "location.north.line.fill", label: "Recenter map") {
                    recenter()
                }
            }
        }
    }

    // MARK: - 3D header button (tap or long-press opens the 3D popup)
    private var threeDHeaderButton: some View {
        Button {
            show3DPopup = true
        } label: {
            Image(systemName: "view.3d")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(ResilixTheme.textPrimary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.10))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
                )
                .liquidGlassCircle(interactive: true)
        }
        .buttonStyle(PressScaleStyle())
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.4)
                .onEnded { _ in show3DPopup = true }
        )
        .accessibilityLabel("3D view options")
    }

    // MARK: - Search bar (dark liquid glass — same style as card/legend/slider)
    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(ResilixTheme.textTertiary)
            // ZStack overlays a custom placeholder so we can control its
            // color (the default TextField placeholder is hard to tint).
            ZStack(alignment: .leading) {
                if searchText.isEmpty {
                    Text("Search places, devices, shelters")
                        .font(ResilixTheme.font(14, .regular))
                        .foregroundStyle(Color.white.opacity(0.35))
                        .allowsHitTesting(false)
                }
                TextField("", text: $searchText)
                    .font(ResilixTheme.font(14, .regular))
                    .foregroundStyle(Color.white)
                    .tint(Color.white)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    searchFocused = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(ResilixTheme.textTertiary)
                }
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
                )
        )
        .liquidGlassRounded(cornerRadius: ResilixTheme.cornerRadiusLarge, interactive: true)
    }

    // MARK: - Legend (dark liquid glass — same style as card/legend/slider)
    private var legendGlass: some View {
        HStack(spacing: 14) {
            LegendRow(color: MapColors.you,     label: "You")
            LegendRow(color: MapColors.direct,  label: "Direct")
            LegendRow(color: MapColors.relay,   label: "Relay")
            LegendRow(color: MapColors.shelter, label: "Shelter")
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(
            RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.7)
                )
        )
        .liquidGlassRounded(cornerRadius: ResilixTheme.cornerRadiusLarge, interactive: false)
    }

    // MARK: - Side button (consistent dark liquid glass)
    private func sideButton(icon: String, label: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isActive ? ResilixTheme.brandCyan : ResilixTheme.textPrimary)
                Text(label)
                    .font(ResilixTheme.font(10, .semibold))
                    .foregroundStyle(isActive ? ResilixTheme.brandCyan : ResilixTheme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: 60, height: 60)
            .background(
                Circle()
                    .fill(Color.white.opacity(isActive ? 0.18 : 0.10))
            )
            .overlay(
                Circle()
                    .stroke(Color.white.opacity(isActive ? 0.35 : 0.18), lineWidth: 0.7)
            )
            .liquidGlassCircle(interactive: true)
            .shadow(color: .black.opacity(0.3), radius: 5, y: 2)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Compact icon button used inside the header next to the compass
    private func headerIconButton(icon: String, label: String, isActive: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isActive ? ResilixTheme.brandCyan : ResilixTheme.textPrimary)
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.white.opacity(isActive ? 0.18 : 0.10))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(isActive ? 0.35 : 0.18), lineWidth: 0.7)
                )
                .liquidGlassCircle(interactive: true)
        }
        .buttonStyle(PressScaleStyle())
        .accessibilityLabel(label)
    }

    // MARK: - Native iOS segmented filter
    // Just the native segmented picker with the iOS 26 liquid-glass capsule
    // modifier. No extra fill, stroke, or padding so the border stays thin
    // and uniform with the rest of the glass elements.
    private var nativeSegmentedFilter: some View {
        Picker("Filter", selection: $filter) {
            ForEach(MapFilter.allCases) { f in
                Text(f.rawValue).tag(f)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: .infinity)
        .frame(height: 36)
        .liquidGlassCapsule(interactive: false)
    }

    // MARK: - 2-finger gesture: drag adjusts pitch, pinch adjusts distance
    private var threeDGesture: some Gesture {
        // 2-finger drag = adjust pitch. Uses simultaneous trackpad-style gesture.
        DragGesture(minimumDistance: 0)
            .updating($gesturePitchDelta) { value, state, _ in
                // Only respond to vertical drag (heuristic). value.translation is cumulative.
                state = Double(value.translation.height) * 0.25
            }
            .onEnded { value in
                guard wants3DCamera else { return }
                let newPitch = pitch3D - Double(value.translation.height) * 0.25
                pitch3D = max(0, min(75, newPitch))
                apply3DCameraIfNeeded()
            }
            .simultaneously(with:
                MagnificationGesture()
                    .updating($gestureDistanceScale) { value, state, _ in
                        state = value
                    }
                    .onEnded { value in
                        // Approximate — store last applied via recenter
                        _ = value
                    }
            )
    }

    // MARK: - Data
    private var peers: [MapPeer] {
        let base = userCoordinate
        return [
            MapPeer(id: "m1", name: "Sarah K.",  kind: .direct,  coordinate: CLLocationCoordinate2D(latitude: base.latitude + 0.0018, longitude: base.longitude - 0.0014)),
            MapPeer(id: "m2", name: "Marcus D.", kind: .direct,  coordinate: CLLocationCoordinate2D(latitude: base.latitude + 0.0009, longitude: base.longitude + 0.0021)),
            MapPeer(id: "m3", name: "ResBot-α",  kind: .relay,   coordinate: CLLocationCoordinate2D(latitude: base.latitude + 0.0024, longitude: base.longitude + 0.0010)),
            MapPeer(id: "m4", name: "James R.",  kind: .relay,   coordinate: CLLocationCoordinate2D(latitude: base.latitude - 0.0015, longitude: base.longitude + 0.0022)),
            MapPeer(id: "m5", name: "Shelter 1", kind: .shelter, coordinate: CLLocationCoordinate2D(latitude: base.latitude - 0.0022, longitude: base.longitude - 0.0010)),
            MapPeer(id: "m6", name: "Shelter 2", kind: .shelter, coordinate: CLLocationCoordinate2D(latitude: base.latitude - 0.0010, longitude: base.longitude - 0.0023)),
        ]
    }

    private var visiblePeers: [MapPeer] {
        let byFilter: [MapPeer]
        switch filter {
        case .all:      byFilter = peers
        case .devices:  byFilter = peers.filter { $0.kind != .shelter }
        case .shelters: byFilter = peers.filter { $0.kind == .shelter }
        case .routes:   byFilter = peers
        }
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return byFilter }
        return byFilter.filter { $0.name.lowercased().contains(query) }
    }

    private func color(for kind: MapPeer.Kind) -> Color {
        switch kind {
        case .direct:  return MapColors.direct
        case .relay:   return MapColors.relay
        case .shelter: return MapColors.shelter
        }
    }

    private func mapStyle(for option: MapStyleOption) -> MapStyle {
        switch option {
        case .standard:
            return .standard(elevation: .flat, pointsOfInterest: .excludingAll)
        case .hybrid:
            return .hybrid(elevation: .realistic, pointsOfInterest: .excludingAll)
        case .satellite:
            return .imagery(elevation: .realistic)
        case .muted:
            return .standard(elevation: .flat, pointsOfInterest: .excludingAll)
        case .transit:
            return .standard(elevation: .flat, pointsOfInterest: .including([.publicTransport]))
        case .threeD:
            return .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
        }
    }

    private func recenter() {
        withAnimation(.easeInOut(duration: 0.35)) {
            apply3DCameraIfNeeded()
        }
    }

    /// Marching-ants animation for the mesh connection lines. Loops the
    /// `dashPhase` from 0 to -(dashOn + dashOff) so the dashes flow from
    /// "You" out to each peer. Runs as a single task while the map is
    /// visible, then auto-cancels when the view disappears.
    private func animateDashPhase() async {
        let period: CGFloat = 10 // dash on (6) + dash off (4)
        while !Task.isCancelled {
            withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                dashPhase = -period
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            // Reset so the next loop starts cleanly at 0.
            withAnimation(.linear(duration: 0)) {
                dashPhase = 0
            }
        }
    }

    /// Apply the camera based on the current style + 3D pitch + 3D mode.
    private func apply3DCameraIfNeeded() {
        let center = userCoordinate
        let effectivePitch = threeDMode == .off ? 0 : pitch3D
        if threeDMode != .off {
            // 3D camera (any map style) — uses the user-controlled pitch.
            let camera = MapCamera(
                centerCoordinate: center,
                distance: 1500,
                heading: 0,
                pitch: effectivePitch
            )
            cameraPosition = .camera(camera)
        } else {
            // 3D off — flat top-down region.
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
            )
        }
    }
}

// MARK: - "You" annotation (Apple Maps iPhone glyph)
private struct YouMapAnnotation: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(MapColors.you.opacity(0.40), lineWidth: 1.2)
                .frame(width: 130, height: 130)
                .scaleEffect(pulse ? 1.1 : 0.9)
                .opacity(pulse ? 0.5 : 0.9)
            Circle()
                .fill(MapColors.you.opacity(0.22))
                .frame(width: 72, height: 72)
            Image(systemName: "iphone.circle.fill")
                .font(.system(size: 52))
                .foregroundStyle(.white, MapColors.you)
                .shadow(color: .black.opacity(0.45), radius: 6, y: 4)
            Text("You")
                .font(ResilixTheme.font(13, .heavy))
                .foregroundStyle(MapColors.you)
                .offset(y: -48)
                .shadow(color: .black.opacity(0.6), radius: 2, y: 1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityLabel("Your device")
    }
}

// MARK: - Peer annotation (Apple Maps iPhone glyph)
private struct PeerMapAnnotation: View {
    let peer: MapPeer

    private var pinColor: Color {
        switch peer.kind {
        case .direct:  return MapColors.direct
        case .relay:   return MapColors.relay
        case .shelter: return MapColors.shelter
        }
    }

    private var iconName: String {
        switch peer.kind {
        case .direct:  return "iphone.circle.fill"
        case .relay:   return "iphone.gen2.circle.fill"
        case .shelter: return "house.circle.fill"
        }
    }

    var body: some View {
        ZStack {
            Image(systemName: iconName)
                .font(.system(size: 44))
                .foregroundStyle(pinColor.opacity(0.35))
                .blur(radius: 6)
            Image(systemName: iconName)
                .font(.system(size: 36))
                .foregroundStyle(.white, pinColor)
                .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
        }
        .accessibilityLabel(peer.name)
    }
}

// MARK: - Legend row
private struct LegendRow: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)
                .shadow(color: color.opacity(0.6), radius: 2)
            Text(label)
                .font(ResilixTheme.font(12, .semibold))
                .foregroundStyle(ResilixTheme.textPrimary)
        }
    }
}

// MARK: - Map peer detail sheet
struct MapPeerDetailSheet: View {
    let peer: MapPeer
    @Environment(\.dismiss) private var dismiss

    private var color: Color {
        switch peer.kind {
        case .direct:  return MapColors.direct
        case .relay:   return MapColors.relay
        case .shelter: return MapColors.shelter
        }
    }

    private var kindLabel: String {
        switch peer.kind {
        case .direct:  return "Direct"
        case .relay:   return "Relay"
        case .shelter: return "Shelter"
        }
    }

    private var iconName: String {
        switch peer.kind {
        case .direct:  return "iphone.circle.fill"
        case .relay:   return "iphone.gen2.circle.fill"
        case .shelter: return "house.circle.fill"
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                Spacer(minLength: 4)
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(color.opacity(0.20))
                            .frame(width: 56, height: 56)
                        Image(systemName: iconName)
                            .font(.system(size: 36))
                            .foregroundStyle(.white, color)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(peer.name)
                            .font(ResilixTheme.font(22, .bold))
                            .foregroundStyle(ResilixTheme.textPrimary)
                        HStack(spacing: 6) {
                            Circle()
                                .fill(ResilixTheme.successGreen)
                                .frame(width: 7, height: 7)
                            Text(kindLabel)
                                .font(ResilixTheme.font(13, .semibold))
                                .foregroundStyle(ResilixTheme.textSecondary)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, ResilixTheme.space20)

                HStack(spacing: 12) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Navigate")
                            .font(ResilixTheme.font(15, .heavy))
                            .tracking(0.4)
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
                            .shadow(color: ResilixTheme.cyanGlowStrong, radius: 8, y: 3)
                    }
                    .buttonStyle(PressScaleStyle())

                    Button {
                        dismiss()
                    } label: {
                        Text("Details")
                            .font(ResilixTheme.font(15, .heavy))
                            .tracking(0.4)
                            .foregroundStyle(ResilixTheme.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.white.opacity(0.10), lineWidth: 0.7)
                                    )
                            )
                            .liquidGlassRounded(cornerRadius: 16, interactive: true)
                    }
                    .buttonStyle(PressScaleStyle())
                }
                .padding(.horizontal, ResilixTheme.space20)
            }
            .padding(.vertical, ResilixTheme.space20)
        }
        .background(ResilixTheme.backgroundPrimary)
    }
}

// MARK: - Layers sheet
struct MapLayersSheet: View {
    @Binding var styleOption: MapStyleOption
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            Capsule()
                .fill(ResilixTheme.separator)
                .frame(width: 36, height: 5)
                .padding(.top, 8)
            Text("Map Layers")
                .font(ResilixTheme.font(18, .bold))
                .foregroundStyle(ResilixTheme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, ResilixTheme.space20)

            VStack(spacing: 10) {
                ForEach(MapStyleOption.allCases) { option in
                    LayerRow(
                        icon: option.icon,
                        title: option.rawValue,
                        subtitle: option.subtitle,
                        selected: styleOption == option
                    ) {
                        styleOption = option
                        dismiss()
                    }
                }
            }
            .padding(.horizontal, ResilixTheme.space20)
            Spacer()
        }
        .padding(.top, ResilixTheme.space8)
        .background(ResilixTheme.backgroundPrimary)
    }
}

private struct LayerRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(ResilixTheme.brandCyan.opacity(0.16))
                        .frame(width: 40, height: 40)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ResilixTheme.brandCyan)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(ResilixTheme.font(15, .semibold))
                        .foregroundStyle(ResilixTheme.textPrimary)
                    Text(subtitle)
                        .font(ResilixTheme.font(12, .regular))
                        .foregroundStyle(ResilixTheme.textSecondary)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(ResilixTheme.brandCyan)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                    )
            )
            .liquidGlassRounded(cornerRadius: 14, interactive: true)
        }
        .buttonStyle(PressScaleStyle())
    }
}

// MARK: - 3D popup sheet (opened by tap or long-press on the 3D button)
// Lets the user pick a 3D mode (Off / Tilted / Cinematic) and adjust the
// tilt (pitch) amount via a slider. Works with any map layer.
struct ThreeDPopupSheet: View {
    @Binding var mode: SurvivalMapView.ThreeDMode
    @Binding var pitch: Double
    let currentStyle: MapStyleOption
    let onChange: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 18) {
            // Drag indicator
            Capsule()
                .fill(ResilixTheme.separator)
                .frame(width: 36, height: 5)
                .padding(.top, 8)

            // Title row
            HStack {
                Image(systemName: "view.3d")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(ResilixTheme.brandCyan)
                Text("3D View")
                    .font(ResilixTheme.font(18, .bold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                Spacer()
                Text(currentStyle.rawValue)
                    .font(ResilixTheme.font(11, .heavy))
                    .tracking(0.6)
                    .foregroundStyle(ResilixTheme.brandCyan)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule().fill(ResilixTheme.brandCyan.opacity(0.16))
                    )
            }
            .padding(.horizontal, ResilixTheme.space20)

            // Mode picker
            VStack(alignment: .leading, spacing: 8) {
                Text("MODE")
                    .font(ResilixTheme.font(11, .heavy))
                    .tracking(1.0)
                    .foregroundStyle(ResilixTheme.textTertiary)
                    .padding(.horizontal, ResilixTheme.space20)
                Picker("Mode", selection: $mode) {
                    ForEach(SurvivalMapView.ThreeDMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, ResilixTheme.space20)
                .onChange(of: mode) { _, newMode in
                    // Snap the pitch to the mode's default when switching modes
                    // (unless the user has already drifted away from the prior
                    // default — then leave the pitch alone).
                    if mode == .off {
                        pitch = 0
                    } else if pitch == 0 || pitch == 30 || pitch == 65 {
                        pitch = newMode.defaultPitch
                    }
                    onChange()
                }
            }

            // Tilt slider
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("TILT")
                        .font(ResilixTheme.font(11, .heavy))
                        .tracking(1.0)
                        .foregroundStyle(ResilixTheme.textTertiary)
                    Spacer()
                    Text("\(Int(pitch))°")
                        .font(ResilixTheme.font(13, .bold))
                        .foregroundStyle(ResilixTheme.textPrimary)
                        .monospacedDigit()
                }
                .padding(.horizontal, ResilixTheme.space20)
                Slider(
                    value: $pitch,
                    in: 0...75,
                    step: 1,
                    onEditingChanged: { _ in onChange() }
                )
                .tint(ResilixTheme.brandCyan)
                .disabled(mode == .off)
                .padding(.horizontal, ResilixTheme.space20)
                Text(mode == .off ? "Set mode to Tilted or Cinematic to adjust the 3D tilt."
                                  : "Drag to tilt the map from top-down (0°) to cinematic (75°).")
                    .font(ResilixTheme.font(11, .regular))
                    .foregroundStyle(ResilixTheme.textSecondary)
                    .padding(.horizontal, ResilixTheme.space20)
            }

            // Quick presets
            HStack(spacing: 10) {
                PresetButton(title: "Flat",   pitch: 0)  { pitch = 0;  mode = .tilted;    onChange() }
                PresetButton(title: "Tilted", pitch: 30) { pitch = 30; mode = .tilted;    onChange() }
                PresetButton(title: "Cinematic", pitch: 65) { pitch = 65; mode = .cinematic; onChange() }
            }
            .padding(.horizontal, ResilixTheme.space20)

            Spacer()
        }
        .padding(.top, ResilixTheme.space8)
        .background(ResilixTheme.backgroundPrimary)
    }
}

private struct PresetButton: View {
    let title: String
    let pitch: Double
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(title)
                    .font(ResilixTheme.font(13, .semibold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                Text("\(Int(pitch))°")
                    .font(ResilixTheme.font(11, .regular))
                    .foregroundStyle(ResilixTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.10), lineWidth: 0.6)
                    )
            )
            .liquidGlassRounded(cornerRadius: 12, interactive: true)
        }
        .buttonStyle(PressScaleStyle())
    }
}
