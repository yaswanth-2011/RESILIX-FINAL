import SwiftUI

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
                Text("Send SOS")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(ResilixTheme.brandNavy)
                    .accessibilityAddTraits(.isHeader)
                
                Text("This will alert nearby devices via mesh. Hold or tap to confirm.")
                    .font(.subheadline)
                    .foregroundStyle(ResilixTheme.textSecondary)
                
                Picker(L("sos.category"), selection: $category) {
                    ForEach(SOSCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("SOS category")
                
                Picker(L("sos.severity"), selection: $severity) {
                    ForEach(SOSSeverity.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("SOS severity")
                
                let scoring = SeverityScoringEngine.score(category: category, severity: severity, note: note)
                HStack {
                    Text(scoring.reason)
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.textSecondary)
                    Spacer()
                    SeverityBadge(severity: severity)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Priority: \(scoring.reason)")
                
                TextField(L("sos.note"), text: $note)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Optional note")
                
                Toggle(L("sos.shareLocation"), isOn: $shareLocation)
                    .tint(ResilixTheme.brandTeal)
                    .accessibilityLabel("Share approximate location")
                
                Text("Location only shared with consent, minimum precision.")
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
                    Text(isHolding ? "Hold to send…" : L("sos.holdToSend"))
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
                .accessibilityLabel("Hold to send SOS")
                .accessibilityHint("Long press for 1.5 seconds to confirm SOS")
                .accessibilityAddTraits(.isButton)
                
                // Alternative tap-to-send for accessibility
                Button(L("sos.send")) {
                    showAlternativeConfirm = true
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(ResilixTheme.brandTeal)
                .accessibilityLabel("Send SOS (alternative)")
                .accessibilityHint("Tap to send SOS without holding")
                
                if let active = app.sosService.activeSOS {
                    ResilixCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Active SOS")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(ResilixTheme.textPrimary)
                            Text(active.category.rawValue)
                                .font(.caption)
                                .foregroundStyle(ResilixTheme.textSecondary)
                            Text("Relaying")
                                .font(.caption2)
                                .foregroundStyle(ResilixTheme.brandTeal)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Active SOS: \(active.category.rawValue), relaying")
                }
                
                if let inc = app.sosService.incidents.first {
                    Text("Delivery: \(inc.acknowledged ? "Delivered" : L("delivery.queued"))")
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
            Button("Send", role: .destructive) {
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
            Text("Send \(severity.label.lowercased()) \(category.label.lowercased()) alert via mesh?")
        }
        .alert(L("sos.confirm"), isPresented: $showAlternativeConfirm) {
            Button(L("sos.cancel"), role: .cancel) {}
            Button("Send", role: .destructive) {
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
            Text("Send \(severity.label.lowercased()) \(category.label.lowercased()) alert via mesh?")
        }
    }
}
