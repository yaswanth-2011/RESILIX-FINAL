import SwiftUI
import PhotosUI
import UIKit

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
                                accessibilityLabel(Text(L("Profile photo")))
                        } else {
                            LogoView(variant: .stacked, height: 48, showTagline: false)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(app.settings.displayName)
                                .font(.headline)
                                .foregroundStyle(ResilixTheme.textPrimary)
                            Text(L("profile.local.mesh.id") + ": \(app.nodeID.prefix(8))")
                                .font(.caption2.monospaced())
                                .foregroundStyle(ResilixTheme.textTertiary)
                            Text(L("Phone number not required"))
                                .font(.caption2)
                                .foregroundStyle(ResilixTheme.textTertiary)
                        }
                    }
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L("profile.summary") + ": \(app.settings.displayName), " + L("profile.mesh.id") + " \(app.nodeID.prefix(8))")

                    HStack(spacing: ResilixTheme.space12) {
                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(L("Choose photo"), systemImage: "photo")
                                .font(.subheadline)
                        }
                        accessibilityLabel(Text(L("Choose a profile photo")))

                        if profilePhoto != nil {
                            Button {
                                Task {
                                    await app.profileService.clearPhoto()
                                    await app.updateSettings { $0.profilePhotoFileName = nil }
                                    photoMessage = L("The profile photo was removed.")
                                }
                            } label: {
                                Text(L("Remove photo"))
                                    .font(.subheadline)
                            }
                        }
                    }
                }
                
                Section(header: Text(L("Mesh"))) {
                    Toggle(L("Relay participation"), isOn: Binding(
                        get: { app.relayManager.isRelayActive },
                        set: { newValue in Task { await app.relayManager.setRelay(newValue) } }
                    ))
                    .tint(ResilixTheme.brandTeal)
                    accessibilityLabel(Text(L("Enable relay participation")))
                    
                    Toggle(L("Location sharing"), isOn: Binding(
                        get: { app.settings.locationSharingEnabled },
                        set: { newValue in Task { await app.updateSettings { $0.locationSharingEnabled = newValue } } }
                    ))
                        .tint(ResilixTheme.brandTeal)
                        accessibilityLabel(Text(L("Share location in SOS and map")))

                    Toggle(L("Message expiry"), isOn: Binding(
                        get: { app.settings.messageExpiryEnabled },
                        set: { newValue in Task { await app.updateSettings { $0.messageExpiryEnabled = newValue } } }
                    ))
                        .tint(ResilixTheme.brandTeal)
                        accessibilityLabel(Text(L("Enable message expiry")))
                    
                    NavigationLink("Permissions", destination: PermissionStatusView())
                    NavigationLink("Diagnostics", destination: DiagnosticsView())
                    NavigationLink("Command Center", destination: CommandCenterView())
                }
                
                Section(header: Text(L("About"))) {
                    HStack {
                        Text(L("Version"))
                            .foregroundStyle(ResilixTheme.textSecondary)
                        Spacer()
                        Text(L("1.0.0 (Prototype)"))
                            .foregroundStyle(ResilixTheme.textTertiary)
                            .font(.caption)
                    }
                    Button(L("Privacy overview")) { showPrivacy = true }
                    Button(L("Replay onboarding")) { showOnboarding = true }
                    #if DEBUG
                    NavigationLink("Demo Mode", destination: DemoSettingsView())
                    #endif
                }
                
                Section {
                    Button(L("Reset local data"), role: .destructive) {
                        showResetConfirm = true
                    }
                    accessibilityLabel(Text(L("Reset all local data")))
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
            .alert(L("Profile"), isPresented: .constant(photoMessage != nil), presenting: photoMessage) { _ in
                Button(L("OK")) { photoMessage = nil }
            } message: { message in
                Text(message)
            }
            .sheet(isPresented: $showPrivacy) { PrivacyView() }
            .sheet(isPresented: $showOnboarding) { OnboardingView() }
            .alert(L("Reset All Data?"), isPresented: $showResetConfirm) {
                Button(L("Cancel"), role: .cancel) {}
                Button(L("Reset"), role: .destructive) {
                    Task { await app.persistence.clearAll() }
                }
            } message: {
                Text(L("This will delete all messages, contacts, resources, and settings. This cannot be undone."))
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
            photoMessage = L("The profile photo was saved.")
        } else {
            photoMessage = L("The photo could not be stored.")
        }
    }
}

struct DemoSettingsView: View {
    @EnvironmentObject var app: ResilixAppModel
    var body: some View {
        List {
            Toggle(L("Demo Mode"), isOn: Binding(
                get: { app.demoController.isDemoMode },
                set: { app.demoController.setDemo($0) }
            ))
            .tint(ResilixTheme.brandTeal)
            accessibilityLabel(Text(L("Enable demo mode")))
            
            Button(L("Reset demo")) {
                app.demoController.reset()
                app.demoController.startDemo()
            }
            accessibilityLabel(Text(L("Reset demo data")))
            
            Section(header: Text(L("Demo log"))) {
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
