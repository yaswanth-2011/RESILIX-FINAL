import SwiftUI

struct PrivacyView: View {
    var body: some View {
        NavigationStack {
            List {
                Section(header: Text(L("Summary"))) {
                    Text(L("Resilix works without internet. Relays forward encrypted packets without reading private content."))
                        .font(.subheadline)
                        .foregroundStyle(ResilixTheme.textSecondary)
                }
                
                Section(header: Text(L("What relays can see"))) {
                    Label(L("Can see: packet size, timing, source/destination IDs (for routing)."), systemImage: "eye")
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.textSecondary)
                    Label(L("Cannot see: private message plaintext (end-to-end encrypted)."), systemImage: "eye.slash")
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.successGreen)
                }
                
                Section(header: Text(L("Location"))) {
                    Text(L("Location sharing requires explicit consent. Approximate location only. Never broadcast exact location without permission."))
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.textSecondary)
                }
                
                Section(header: Text(L("Map reports"))) {
                    Text(L("Community reports are marked as unverified until verified by rescue role in demo. Do not assume unverified locations are safe."))
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.textSecondary)
                }
                
                Section {
                    Text(L("This is a prototype. No formal security certification. Use standard cryptographic primitives, not custom ciphers."))
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
