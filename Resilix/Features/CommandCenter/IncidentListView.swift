import SwiftUI

struct IncidentListView: View {
    var filter: SOSSeverity?
    var incidents: [Incident]
    @EnvironmentObject var app: ResilixAppModel
    
    var body: some View {
        List {
            if incidents.isEmpty {
                EmptyStateView(
                    title: L("No incidents"),
                    subtitle: L("No active SOS incidents."),
                    icon: "shield.lefthalf.filled"
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(incidents) { inc in
                    NavigationLink(destination: IncidentDetailView(incident: inc)) {
                        IncidentRow(incident: inc)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(ResilixTheme.bgPrimary)
    }
}

struct IncidentRow: View {
    let incident: Incident
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                SeverityBadge(severity: incident.severity)
                Text(incident.category.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                Spacer()
                if incident.acknowledged {
                    ResilixStatusBadge(text: "Ack", color: ResilixTheme.successGreen)
                }
            }
            HStack {
                Text(incident.note ?? L("SOS"))
                    .font(.caption)
                    .foregroundStyle(ResilixTheme.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text("\(incident.hops ?? 0) " + L("ui.hops"))
                    .font(.caption2)
                    .foregroundStyle(ResilixTheme.textTertiary)
            }
            HStack {
                Text(incident.createdAt, style: .relative)
                    .font(.caption2)
                    .foregroundStyle(ResilixTheme.textTertiary)
                Spacer()
                Text(incident.routeSummary ?? "A → B → C")
                    .font(.caption2)
                    .foregroundStyle(ResilixTheme.textTertiary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(incident.category.label) " + L("ui.incident") + ", \(incident.severity.label) " + L("ui.severity") + ", \(incident.hops ?? 0) " + L("ui.hops"))
    }
}
