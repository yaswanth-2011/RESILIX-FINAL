import SwiftUI
import MapKit

struct IncidentDetailView: View {
    var incident: Incident
    @EnvironmentObject var app: ResilixAppModel
    @State private var isAcknowledging = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ResilixTheme.space16) {
                HStack {
                    SeverityBadge(severity: incident.severity)
                    Text(incident.category.label)
                        .font(.headline)
                        .foregroundStyle(ResilixTheme.textPrimary)
                    Spacer()
                    Text(incident.status.rawValue.capitalized)
                        .font(.caption2.weight(.semibold))
                        .padding(6)
                        .background(ResilixTheme.bgSecondary)
                        .clipShape(Capsule())
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(incident.category.label) incident, \(incident.severity.label) severity, \(incident.status.rawValue)")
                
                if let n = incident.note {
                    Text(n)
                        .font(.body)
                        .foregroundStyle(ResilixTheme.textPrimary)
                }
                
                RoutePathView(hops: incident.routeSummary?.components(separatedBy: " → ") ?? ["A", "B", "C"])
                    .accessibilityLabel("Route: \(incident.routeSummary ?? "A to B to C")")
                
                HStack {
                    Label("\(incident.hops ?? 2) hops", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.textSecondary)
                    Spacer()
                    Text(incident.lastUpdateAt, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(ResilixTheme.textTertiary)
                }
                
                if let lat = incident.latitude, let lon = incident.longitude {
                    Map(initialPosition: .region(
                        MKCoordinateRegion(
                            center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                        )
                    )) {
                        Marker("Incident", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                            .tint(ResilixTheme.emergencyRed)
                    }
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: ResilixTheme.cornerRadiusMedium))
                    .accessibilityLabel("Map showing incident location")
                }
                
                if !incident.acknowledged {
                    Button {
                        acknowledgeIncident()
                    } label: {
                        if isAcknowledging {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Acknowledge")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(ResilixTheme.brandTeal)
                    .disabled(isAcknowledging)
                    .accessibilityLabel("Acknowledge incident")
                    Text("Acknowledgement propagates through mesh.")
                        .font(.caption2)
                        .foregroundStyle(ResilixTheme.textTertiary)
                } else {
                    ResilixStatusBadge(text: "Acknowledged", color: ResilixTheme.successGreen)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(ResilixTheme.space16)
        }
        .background(ResilixTheme.bgPrimary)
        .navigationTitle("Incident")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private func acknowledgeIncident() {
        isAcknowledging = true
        Task {
            await app.sosService.acknowledge(incident.id)
            isAcknowledging = false
        }
    }
}
