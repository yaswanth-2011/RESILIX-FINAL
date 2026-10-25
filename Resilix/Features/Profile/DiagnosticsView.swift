import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var app: ResilixAppModel
    @State private var showDetails = false
    
    var body: some View {
        List {
            Section(header: Text(L("diagnostics.transports"))) {
                DiagnosticRow(label: "Bluetooth", value: app.diagnosticsService.snapshot.bluetoothState)
                DiagnosticRow(label: "P2P Wi-Fi", value: app.diagnosticsService.snapshot.p2pWiFiState)
                DiagnosticRow(label: "Wi-Fi Aware", value: app.diagnosticsService.snapshot.wifiAwareState)
                if app.diagnosticsService.snapshot.isDemo {
                    ResilixStatusBadge(text: L("Demo values"), color: ResilixTheme.brandAmber)
                        .accessibilityLabel(Text(L("Demo mode active")))
                }
            }
            
            Section(header: Text(L("diagnostics.mesh"))) {
                DiagnosticRow(label: L("Connected peers"), value: "\(app.diagnosticsService.snapshot.connectedCount)")
                DiagnosticRow(label: "Discovered", value: "\(app.diagnosticsService.snapshot.discoveredCount)")
                DiagnosticRow(label: L("Routes"), value: "\(app.diagnosticsService.snapshot.routeCount)")
                DiagnosticRow(label: L("Queued packets"), value: "\(app.diagnosticsService.snapshot.queueCount)")
                DiagnosticRow(label: "Forwarded", value: "\(app.diagnosticsService.snapshot.forwardedCount)")
                DiagnosticRow(label: L("Dropped duplicates"), value: "\(app.diagnosticsService.snapshot.droppedDuplicates)")
                DiagnosticRow(label: "Expired", value: "\(app.diagnosticsService.snapshot.expiredCount)")
                DiagnosticRow(label: L("Relay"), value: app.diagnosticsService.snapshot.relayActive ? "Active" : "Inactive")
            }
            
            Section(header: Text(L("diagnostics.system"))) {
                DiagnosticRow(label: L("Protocol version"), value: "\(app.diagnosticsService.snapshot.protocolVersion)")
                DiagnosticRow(label: "Persistence", value: app.diagnosticsService.snapshot.persistenceStatus)
                DiagnosticRow(label: L("Permissions"), value: app.diagnosticsService.snapshot.permissionStatus)
                DiagnosticRow(label: L("Last event"), value: app.diagnosticsService.snapshot.lastTransportEvent ?? "—")
                DiagnosticRow(label: "Snapshot", value: app.diagnosticsService.snapshot.timestamp.formatted(date: .abbreviated, time: .shortened))
            }
            
            Section {
                DisclosureGroup(L("diagnostics.developerDetails"), isExpanded: $showDetails) {
                    Text(L("Packet queue inspected without plaintext. Logs contain packet IDs only."))
                        .font(.caption2)
                        .foregroundStyle(ResilixTheme.textTertiary)
                    Text(L("Battery impact: discovery stops when idle; backoff on retries; bounded queues."))
                        .font(.caption2)
                        .foregroundStyle(ResilixTheme.textTertiary)
                }
                
                Button(L("diagnostics.refresh")) {
                    Task {
                        await app.diagnosticsService.refresh(
                            transports: app.meshController.availableTransports,
                            queueCount: await app.meshController.queueCount(),
                            relayActive: app.relayManager.isRelayActive,
                            isDemo: app.demoController.isDemoMode,
                            routingEngine: app.routingEngine,
                            relayManager: app.relayManager
                        )
                    }
                }
                .accessibilityLabel(Text(L("Refresh diagnostics")))
                
                Button(L("diagnostics.connectivityTest")) {
                    Task {
                        await app.diagnosticsService.refresh(
                            transports: app.meshController.availableTransports,
                            queueCount: 0,
                            relayActive: app.relayManager.isRelayActive,
                            isDemo: false,
                            routingEngine: app.routingEngine,
                            relayManager: app.relayManager
                        )
                    }
                }
                .accessibilityLabel(Text(L("Run connectivity test")))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ResilixTheme.bgPrimary)
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable {
            await app.diagnosticsService.refresh(
                transports: app.meshController.availableTransports,
                queueCount: await app.meshController.queueCount(),
                relayActive: app.relayManager.isRelayActive,
                isDemo: app.demoController.isDemoMode,
                routingEngine: app.routingEngine,
                relayManager: app.relayManager
            )
        }
        .task {
            await app.diagnosticsService.refresh(
                transports: app.meshController.availableTransports,
                queueCount: await app.meshController.queueCount(),
                relayActive: app.relayManager.isRelayActive,
                isDemo: app.demoController.isDemoMode,
                routingEngine: app.routingEngine,
                relayManager: app.relayManager
            )
        }
    }
    
    struct DiagnosticRow: View {
        var label: String
        var value: String
        
        var body: some View {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(ResilixTheme.textSecondary)
                Spacer()
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ResilixTheme.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(label): \(value)")
        }
    }
}
