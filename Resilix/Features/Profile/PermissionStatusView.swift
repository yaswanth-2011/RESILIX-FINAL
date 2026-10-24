import SwiftUI

struct PermissionStatusView: View {
    @EnvironmentObject var app: ResilixAppModel
    
    var body: some View {
        List {
            StatusRow(
                title: L("permissions.bluetooth"),
                state: app.permissionService.bluetoothState,
                detail: "Mesh discovery requires Bluetooth. Enable in Settings if denied."
            )
            StatusRow(
                title: L("permissions.localNetwork"),
                state: app.permissionService.localNetworkState,
                detail: "P2P Wi-Fi uses local network discovery. Denied limits peer discovery."
            )
            StatusRow(
                title: L("permissions.location"),
                state: app.permissionService.locationState,
                detail: "Map and SOS location sharing need location. Denied limits map features."
            )
            Button(L("permissions.openSettings")) {
                app.permissionService.openSettings()
            }
            .foregroundStyle(ResilixTheme.brandTeal)
            .accessibilityLabel("Open system settings for permissions")
        }
        .navigationTitle("Permissions")
        .background(ResilixTheme.bgPrimary)
        .scrollContentBackground(.hidden)
        .onAppear { app.permissionService.refresh() }
    }
    
    struct StatusRow: View {
        var title: String
        var state: PermissionState
        var detail: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ResilixTheme.textPrimary)
                    Spacer()
                    Text(state.rawValue)
                        .font(.caption2.weight(.semibold))
                        .padding(6)
                        .background(color.opacity(0.15))
                        .clipShape(Capsule())
                        .foregroundStyle(color)
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(ResilixTheme.textSecondary)
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(title): \(state.rawValue)")
        }
        
        var color: Color {
            switch state {
            case .authorized: return ResilixTheme.successGreen
            case .denied, .restricted: return ResilixTheme.emergencyRed
            default: return ResilixTheme.textTertiary
            }
        }
    }
}
