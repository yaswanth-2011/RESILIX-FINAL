import SwiftUI

struct CommandCenterView: View {
    @EnvironmentObject var app: ResilixAppModel
    @State private var filter: SOSSeverity? = nil
    @State private var showMap = true
    @State private var isLoading = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $showMap) {
                    Text("List").tag(false)
                    Text("Split").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(ResilixTheme.space16)
                .accessibilityLabel("View mode")
                
                if showMap {
                    NavigationSplitView {
                        IncidentListView(filter: filter, incidents: filtered)
                    } detail: {
                        if let first = filtered.first {
                            IncidentDetailView(incident: first)
                        } else {
                            EmptyStateView(
                                title: "No incidents",
                                subtitle: "No active SOS incidents.",
                                icon: "shield.lefthalf.filled"
                            )
                        }
                    }
                } else {
                    IncidentListView(filter: filter, incidents: filtered)
                }
            }
            .background(ResilixTheme.bgPrimary)
            .navigationTitle("Command Center")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("All") { filter = nil }
                        ForEach(SOSSeverity.allCases, id: \.self) { s in
                            Button(s.label) { filter = s }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    .accessibilityLabel("Filter by severity")
                }
            }
            .refreshable {
                await loadIncidents()
            }
            .overlay {
                if isLoading && filtered.isEmpty {
                    LoadingStateView()
                }
            }
            .task {
                await loadIncidents()
            }
        }
    }
    
    private func loadIncidents() async {
        isLoading = true
        try? await Task.sleep(nanoseconds: 200_000_000)
        isLoading = false
    }
    
    var filtered: [Incident] {
        let base = app.sosService.incidents.isEmpty ? [DemoDataFactory.sos] : app.sosService.incidents
        let sorted = base.sorted { a, b in
            if a.severity != b.severity {
                return SeverityScoringEngine.score(category: a.category, severity: a.severity, note: a.note).score >
                       SeverityScoringEngine.score(category: b.category, severity: b.severity, note: b.note).score
            }
            return a.createdAt > b.createdAt
        }
        if let f = filter { return sorted.filter { $0.severity == f } }
        return sorted
    }
}
