import SwiftUI
import MapKit
import UniformTypeIdentifiers
import CoreLocation
import Foundation

/// Offline map packs: import, activation, storage and rendering.
///
/// The preview renders the tiles of the selected pack from the local file —
/// no network access is needed once the pack was imported.
struct OfflineMapSheet: View {
    @EnvironmentObject var app: ResilixAppModel
    @Environment(\.dismiss) private var dismiss

    @State private var showImporter = false
    @State private var message: String?
    @State private var previewPackID: String?

    private var service: MapPackService { app.mapPackService }

    var body: some View {
        NavigationStack {
            ZStack {
                ResilixTheme.backgroundPrimary.ignoresSafeArea()

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: ResilixTheme.space16) {
                        statusCard

                        if service.packs.isEmpty {
                            emptyCard
                        } else {
                            preview
                            ForEach(service.packs) { pack in
                                packCard(pack)
                            }
                        }
                    }
                    .padding(.horizontal, ResilixTheme.space20)
                    .padding(.vertical, ResilixTheme.space16)
                }
            }
            .navigationTitle("Offline Maps")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("Done")) { dismiss() }
                        .font(ResilixTheme.font(15, .semibold))
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showImporter = true
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .accessibilityLabel(Text(L("Import a map pack")))
                }
            }
            .fileImporter(isPresented: $showImporter,
                          allowedContentTypes: [.data],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { Task { await importPack(url) } }
                case .failure:
                    message = L("The map pack could not be opened.")
                }
            }
            .alert(L("Offline Maps"), isPresented: .constant(message != nil), presenting: message) { _ in
                Button(L("OK")) { message = nil }
            } message: { text in
                Text(text)
            }
        }
    }

    // MARK: - Status

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: ResilixTheme.space8) {
            HStack {
                Text(service.activePack == nil ? L("No offline map installed") : L("Offline map active"))
                    .font(ResilixTheme.font(16, .semibold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: Int64(service.storageUsedBytes), countStyle: .file))
                    .font(ResilixTheme.font(13, .semibold))
                    .foregroundStyle(ResilixTheme.brandCyan)
            }
            Text(service.activePack == nil
                 ? L("The map above uses the online Apple tiles. Import an .mbtiles pack to use the map without internet.")
                 : String(format: L("Tiles are rendered from “%@” on this device."), service.activePack?.name ?? ""))
                .font(ResilixTheme.font(12, .regular))
                .foregroundStyle(ResilixTheme.textSecondary)
        }
        .padding(ResilixTheme.space16)
        .background(ResilixTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                .stroke(ResilixTheme.separator.opacity(0.6), lineWidth: 0.6)
        )
    }

    private var emptyCard: some View {
        VStack(spacing: ResilixTheme.space12) {
            Image(systemName: "map")
                .font(.system(size: 34))
                .foregroundStyle(ResilixTheme.textTertiary)
            Text(L("No map pack on this device"))
                .font(ResilixTheme.font(15, .semibold))
                .foregroundStyle(ResilixTheme.textPrimary)
            Text(L("Import an .mbtiles file (for example from OpenStreetMap) to keep the map available offline."))
                .font(ResilixTheme.font(12, .regular))
                .foregroundStyle(ResilixTheme.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                showImporter = true
            } label: {
                Text(L("Import map pack"))
                    .font(ResilixTheme.font(15, .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(ResilixTheme.brandCyan)
                    .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusMedium, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, ResilixTheme.space24)
        .padding(.horizontal, ResilixTheme.space16)
        .background(ResilixTheme.surfacePrimary)
        .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous))
    }

    // MARK: - Preview

    @ViewBuilder
    private var preview: some View {
        if let pack = previewPack {
            VStack(alignment: .leading, spacing: ResilixTheme.space8) {
                Text(L("map.preview") + " · \(pack.name)")
                    .font(ResilixTheme.font(14, .semibold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                OfflineMapPreview(pack: pack,
                                  overlay: service.tileOverlay(for: pack),
                                  userCoordinate: app.locationService.coordinate,
                                  peers: peerAnnotations)
                    .frame(height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusLarge, style: .continuous)
                            .stroke(ResilixTheme.separator.opacity(0.6), lineWidth: 0.6)
                    )
            }
        }
    }

    private var previewPack: MapPackDescriptor? {
        if let previewPackID, let pack = service.packs.first(where: { $0.id == previewPackID }) {
            return pack
        }
        return service.activePack
    }

    private var peerAnnotations: [OfflineMapPeer] {
        app.meshController.peers.compactMap { node in
            guard let latitude = node.latitude, let longitude = node.longitude else { return nil }
            return OfflineMapPeer(id: node.id,
                                  name: node.displayName ?? node.alias,
                                  coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude))
        }
    }

    // MARK: - Pack card

    private func packCard(_ pack: MapPackDescriptor) -> some View {
        VStack(alignment: .leading, spacing: ResilixTheme.space8) {
            HStack {
                Text(pack.name)
                    .font(ResilixTheme.font(15, .semibold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                Spacer()
                if service.activePackID == pack.id {
                    ResilixStatusBadge(text: "Active", color: ResilixTheme.successGreen)
                }
            }
            Text(L("map.zoom") + " \(pack.minZoom)–\(pack.maxZoom) · \(pack.coordinateText)")
                .font(ResilixTheme.font(12, .regular))
                .foregroundStyle(ResilixTheme.textSecondary)
            Text(ByteCountFormatter.string(fromByteCount: Int64(pack.byteCount), countStyle: .file)
                 + " · imported \(pack.importedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(ResilixTheme.font(11, .regular))
                .foregroundStyle(ResilixTheme.textTertiary)
            if let sha = pack.sha256 {
                Text(L("map.sha256") + " \(sha.prefix(16))…")
                    .font(ResilixTheme.font(11, .regular))
                    .foregroundStyle(ResilixTheme.textTertiary)
            }

            HStack(spacing: ResilixTheme.space12) {
                Button {
                    service.activate(packID: pack.id)
                    previewPackID = pack.id
                } label: {
                    Text(service.activePackID == pack.id ? L("Active") : L("Activate"))
                        .font(ResilixTheme.font(14, .semibold))
                        .foregroundStyle(service.activePackID == pack.id ? ResilixTheme.textSecondary : .white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(service.activePackID == pack.id ? ResilixTheme.surfacePrimary : ResilixTheme.brandCyan)
                        .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusMedium, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    previewPackID = pack.id
                } label: {
                    Text(L("Preview"))
                        .font(ResilixTheme.font(14, .semibold))
                        .foregroundStyle(ResilixTheme.textPrimary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(ResilixTheme.surfacePrimary)
                        .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusMedium, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    Task { await service.deletePack(pack.id) }
                } label: {
                    Text(L("Delete"))
                        .font(ResilixTheme.font(14, .semibold))
                        .foregroundStyle(ResilixTheme.emergencyRed)
                }
                .buttonStyle(.plain)
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

    private func importPack(_ url: URL) async {
        do {
            let pack = try await service.importPack(from: url)
            previewPackID = pack.id
            message = String(format: L("“%@” was imported."), pack.name)
        } catch {
            message = error.localizedDescription
        }
    }
}

/// A peer marker inside the offline map preview.
struct OfflineMapPeer: Identifiable {
    let id: String
    let name: String
    let coordinate: CLLocationCoordinate2D
}

/// Renders an offline tile overlay with the local position and the peers.
struct OfflineMapPreview: UIViewRepresentable {
    let pack: MapPackDescriptor
    let overlay: MKTileOverlay?
    let userCoordinate: CLLocationCoordinate2D?
    let peers: [OfflineMapPeer]

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator
        mapView.isRotateEnabled = false
        mapView.showsUserLocation = userCoordinate != nil
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        // `MKTileOverlay` exposes no template for comparison; identity is the
        // only reliable test for "this exact overlay is already installed".
        if let overlay, !mapView.overlays.contains(where: { ($0 as? MKTileOverlay) === overlay }) {
            mapView.removeOverlays(mapView.overlays)
            mapView.addOverlay(overlay, level: .aboveLabels)
        }
        let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: pack.centerLatitude,
                                                                       longitude: pack.centerLongitude),
                                        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05))
        if !context.coordinator.didSetRegion {
            mapView.setRegion(region, animated: false)
            context.coordinator.didSetRegion = true
        }

        mapView.removeAnnotations(mapView.annotations.filter { !($0 is MKUserLocation) })
        for peer in peers {
            let annotation = MKPointAnnotation()
            annotation.coordinate = peer.coordinate
            annotation.title = peer.name
            mapView.addAnnotation(annotation)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var didSetRegion = false

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let tileOverlay = overlay as? MKTileOverlay else {
                return MKOverlayRenderer(overlay: overlay)
            }
            return MKTileOverlayRenderer(tileOverlay: tileOverlay)
        }
    }
}
