import SwiftUI
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject var app: ResilixAppModel
    @State private var showDiagnostics = false
    @State private var showPrivacy = false
    @State private var showOnboarding = false
    @State private var showResetConfirm = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var photoMessage: String?

    /// The stored profile photo (or the logo placeholder).
    private var profilePhoto: UIImage? {
        app.profileService.loadPhoto()
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        if let photo = profilePhoto {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 48, height: 48)
                                .clipShape(Circle())
                                .overlay(Circle().stroke(ResilixTheme.separator.opacity(0.6), lineWidth: 0.6))
                                .accessibilityLabel("Profile photo")
                        } else {
                            LogoView(variant: .stacked, height: 48, showTagline: false)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.settings.displayName)
                                .font(.headline)
                                .foregroundStyle(ResilixTheme.textPrimary)
                            Text("Local mesh ID: \(app.nodeID.prefix(8))")
                                .font(.caption2.monospaced())
                                .foregroundStyle(ResilixTheme.textTertiary)
                            Text("Phone number not required")
                                .font(.caption2)
                                .foregroundStyle(ResilixTheme.textTertiary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Profile: \(app.settings.displayName), mesh ID \(app.nodeID.prefix(8))")

                    HStack(spacing: ResilixTheme.space12) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label("Choose photo", systemImage: "photo")
                                .font(.subheadline)
                        }
                        .accessibilityLabel("Choose a profile photo")

                        if profilePhoto != nil {
                            Button {
                                Task {
                                    await app.profileService.clearPhoto()
                                    await app.updateSettings { $0.profilePhotoFileName = nil }
                                    photoMessage = "The profile photo was removed."
                                }
                            } label: {
                                Text("Remove photo")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                
                Section(header: Text("Mesh")) {
                    Toggle("Relay participation", isOn: Binding(
                        get: { app.relayManager.isRelayActive },
                        set: { newValue in Task { await app.relayManager.setRelay(newValue) } }
                    ))
                    .tint(ResilixTheme.brandTeal)
                    .accessibilityLabel("Enable relay participation")
                    
                    Toggle("Location sharing", isOn: Binding(
                        get: { app.settings.locationSharingEnabled },
                        set: { newValue in Task { await app.updateSettings { $0.locationSharingEnabled = newValue } } }
                    ))
                        .tint(ResilixTheme.brandTeal)
                        .accessibilityLabel("Share location in SOS and map")

                    Toggle("Message expiry", isOn: Binding(
                        get: { app.settings.messageExpiryEnabled },
                        set: { newValue in Task { await app.updateSettings { $0.messageExpiryEnabled = newValue } } }
                    ))
                        .tint(ResilixTheme.brandTeal)
                        .accessibilityLabel("Enable message expiry")
                    
                    NavigationLink("Permissions", destination: PermissionStatusView())
                    NavigationLink("Diagnostics", destination: DiagnosticsView())
                    NavigationLink("Command Center", destination: CommandCenterView())
                }
                
                Section(header: Text("About")) {
                    HStack {
                        Text("Version")
                            .foregroundStyle(ResilixTheme.textSecondary)
                        Spacer()
                        Text("1.0.0 (Prototype)")
                            .foregroundStyle(ResilixTheme.textTertiary)
                            .font(.caption)
                    }
                    Button("Privacy overview") { showPrivacy = true }
                    Button("Replay onboarding") { showOnboarding = true }
                    #if DEBUG
                    NavigationLink("Demo Mode", destination: DemoSettingsView())
                    #endif
                }
                
                Section {
                    Button("Reset local data", role: .destructive) {
                        showResetConfirm = true
                    }
                    .accessibilityLabel("Reset all local data")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ResilixTheme.bgPrimary)
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: selectedPhoto) { _, item in
                Task { await savePhoto(item) }
            }
            .alert("Profile", isPresented: .constant(photoMessage != nil), presenting: photoMessage) { _ in
                Button("OK") { photoMessage = nil }
            } message: { message in
                Text(message)
            }
            .sheet(isPresented: $showPrivacy) { PrivacyView() }
            .sheet(isPresented: $showOnboarding) { OnboardingView() }
            .alert("Reset All Data?", isPresented: $showResetConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    Task { await app.persistence.clearAll() }
                }
            } message: {
                Text("This will delete all messages, contacts, resources, and settings. This cannot be undone.")
            }
        }
    }
}

extension ProfileView {
    /// Stores the selected photo and keeps the settings in sync.
    func savePhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        if await app.profileService.setPhoto(image) {
            await app.updateSettings { $0.profilePhotoFileName = app.profileService.photoFileName }
            photoMessage = "The profile photo was saved."
        } else {
            photoMessage = "The photo could not be stored."
        }
    }
}

struct DemoSettingsView: View {
    @EnvironmentObject var app: ResilixAppModel
    var body: some View {
        List {
            Toggle("Demo Mode", isOn: Binding(
                get: { app.demoController.isDemoMode },
                set: { app.demoController.setDemo($0) }
            ))
            .tint(ResilixTheme.brandTeal)
            .accessibilityLabel("Enable demo mode")
            
            Button("Reset demo") {
                app.demoController.reset()
                app.demoController.startDemo()
            }
            .accessibilityLabel("Reset demo data")
            
            Section(header: Text("Demo log")) {
                ForEach(app.demoController.demoLog, id: \.self) { log in
                    Text(log)
                        .font(.caption2)
                        .foregroundStyle(ResilixTheme.textSecondary)
                }
            }
        }
        .navigationTitle("Demo")
        .background(ResilixTheme.bgPrimary)
        .scrollContentBackground(.hidden)
    }
}
