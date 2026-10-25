import SwiftUI
import Foundation

struct SOSView: View {
    @EnvironmentObject var app: ResilixAppModel
    @State private var category: SOSCategory = .medical
    @State private var severity: SOSSeverity = .critical
    @State private var note = ""
    @State private var shareLocation = false
    @State private var showConfirm = false
    @State private var isHolding = false
    @State private var progress: CGFloat = 0
    @State private var showAlternativeConfirm = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ResilixTheme.space16) {
                Text(L("Send SOS"))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ResilixTheme.brandNavy)
                    .accessibilityAddTraits(.isHeader)
                
                Text(L("This will alert nearby devices via mesh. Hold or tap to confirm."))
                    .font(.subheadline)
                    .foregroundStyle(ResilixTheme.textSecondary)
                
                Picker(L("sos.category"), selection: $category) {
                    ForEach(SOSCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                accessibilityLabel(Text(L("SOS category")))
                
                Picker(L("sos.severity"), selection: $severity) {
                    ForEach(SOSSeverity.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                accessibilityLabel(Text(L("SOS severity")))
                
                let scoring = SeverityScoringEngine.score(category: category, severity: severity, note: note)
                HStack {
                    Text(scoring.reason)
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.textSecondary)
                    Spacer()
                    SeverityBadge(severity: severity)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(L("sos.priority") + ": \(scoring.reason)")
                
                TextField(L("sos.note"), text: $note)
                    .textFieldStyle(.roundedBorder)
                    accessibilityLabel(Text(L("Optional note")))
                
                Toggle(L("sos.shareLocation"), isOn: $shareLocation)
                    .tint(ResilixTheme.brandTeal)
                    accessibilityLabel(Text(L("Share approximate location")))
                
                Text(L("Location only shared with consent, minimum precision."))
                    .font(.caption2)
                    .foregroundStyle(ResilixTheme.textTertiary)
                
                // Hold to send
                GeometryReader { geo in
                    ZStack {
                        Capsule()
                            .fill(ResilixTheme.textTertiary.opacity(0.15))
                            .frame(height: 56)
                        Capsule()
                            .fill(ResilixTheme.emergencyRed)
                            .frame(width: progress * (geo.size.width - 32), height: 56)
                            .animation(.linear, value: progress)
                    Text(isHolding ? L("Hold to send…") : L("sos.holdToSend"))
                        .font(.headline)
                        .foregroundStyle(isHolding ? .white : ResilixTheme.emergencyRed)
                    }
                }
                .frame(height: 56)
                .gesture(
                    LongPressGesture(minimumDuration: 1.5)
                        .onChanged { v in
                            isHolding = v
                            withAnimation { progress = v ? 1 : 0 }
                        }
                        .onEnded { _ in
                            showConfirm = true
                            isHolding = false
                            progress = 0
                        }
                )
                accessibilityLabel(Text(L("Hold to send SOS")))
                accessibilityHint(Text(L("Long press for 1.5 seconds to confirm SOS")))
                .accessibilityAddTraits(.isButton)
                
                // Alternative tap-to-send for accessibility
                Button(L("sos.send")) {
                    showAlternativeConfirm = true
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(ResilixTheme.brandTeal)
                accessibilityLabel(Text(L("Send SOS (alternative)")))
                accessibilityHint(Text(L("Tap to send SOS without holding")))
                
                if let active = app.sosService.activeSOS {
                    ResilixCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Active SOS"))
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ResilixTheme.textPrimary)
                            Text(active.category.label)
                                .font(.caption)
                                .foregroundStyle(ResilixTheme.textSecondary)
                            Text(L("Relaying"))
                                .font(.caption2)
                                .foregroundStyle(ResilixTheme.brandTeal)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L("sos.active") + ": \(active.category.label), " + L("sos.relaying"))
                }
                
                if let inc = app.sosService.incidents.first {
                    Text(L("sos.delivery") + ": \(inc.acknowledged ? L("delivery.delivered") : L("delivery.queued"))")
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.textSecondary)
                }
            }
            .padding(ResilixTheme.space16)
        }
        .background(ResilixTheme.bgPrimary)
        .navigationTitle(L("sos.title"))
        .navigationBarTitleDisplayMode(.inline)
        .alert(L("sos.confirm"), isPresented: $showConfirm) {
            Button(L("sos.cancel"), role: .cancel) {}
            Button(L("Send"), role: .destructive) {
                Task {
                    try? await app.sosService.dispatch(
                        category: category,
                        severity: severity,
                        note: note.isEmpty ? nil : note,
                        lat: shareLocation ? 37.7749 : nil,
                        lon: shareLocation ? -122.4194 : nil,
                        source: app.nodeID
                    )
                }
            }
        } message: {
            Text(L("sos.send.prompt") + " \(severity.label.lowercased()) \(category.label.lowercased()) " + L("sos.send.prompt.tail"))
        }
        .alert(L("sos.confirm"), isPresented: $showAlternativeConfirm) {
            Button(L("sos.cancel"), role: .cancel) {}
            Button(L("Send"), role: .destructive) {
                Task {
                    try? await app.sosService.dispatch(
                        category: category,
                        severity: severity,
                        note: note.isEmpty ? nil : note,
                        lat: shareLocation ? 37.7749 : nil,
                        lon: shareLocation ? -122.4194 : nil,
                        source: app.nodeID
                    )
                }
            }
        } message: {
            Text(String(format: L("Send %@ %@ alert via mesh?"), severity.label.lowercased(), category.label.lowercased()))
        }
    }
}
