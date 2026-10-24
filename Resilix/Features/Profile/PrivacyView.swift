import SwiftUI

struct PrivacyView: View {
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Summary")) {
                    Text("Resilix works without internet. Relays forward encrypted packets without reading private content.")
                        .font(.subheadline)
                        .foregroundStyle(ResilixTheme.textSecondary)
                }
                
                Section(header: Text("What relays can see")) {
                    Label("Can see: packet size, timing, source/destination IDs (for routing).", systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.textSecondary)
                    Label("Cannot see: private message plaintext (end-to-end encrypted).", systemImage: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.successGreen)
                }
                
                Section(header: Text("Location")) {
                    Text("Location sharing requires explicit consent. Approximate location only. Never broadcast exact location without permission.")
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.textSecondary)
                }
                
                Section(header: Text("Map reports")) {
                    Text("Community reports are marked as unverified until verified by rescue role in demo. Do not assume unverified locations are safe.")
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.textSecondary)
                }
                
                Section {
                    Text("This is a prototype. No formal security certification. Use standard cryptographic primitives, not custom ciphers.")
                        .font(.caption2)
                        .foregroundStyle(ResilixTheme.textTertiary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ResilixTheme.bgPrimary)
            .navigationTitle("Privacy")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
