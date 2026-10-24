import SwiftUI
import PhotosUI
import AVFoundation

// MARK: - WhatsApp-style message thread
struct MessageThreadView: View {
    var message: MeshMessage
    @EnvironmentObject var app: ResilixAppModel
    @State private var draft = ""
    @State private var messages: [ThreadMessage] = []
    @State private var isMuted = false
    @AppStorage("mutedThreads") private var mutedThreads: String = ""
    @State private var showClearConfirm = false
    @State private var showAttachmentOptions = false
    @State private var showCamera = false
    @State private var showPhotoPicker = false
    @State private var showVoiceRecorder = false
    @State private var selectedPhoto: PhotosPickerItem?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Custom top header — avatar + name + status pill on the page
            // background (not in the iOS nav toolbar, so no liquid-glass box
            // bleeds behind the avatar and the name/info are fully visible).
            threadHeader
                .padding(.horizontal, ResilixTheme.space16)
                .padding(.top, ResilixTheme.space8)
                .padding(.bottom, ResilixTheme.space8)
            routeBar
            meshStatusBar
            messagesScroll
            inputBar
        }
        .background(ResilixTheme.backgroundPrimary.ignoresSafeArea())
        .toolbar(.hidden, for: .tabBar)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarHidden(true)
        .confirmationDialog("Clear this chat?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear Chat", role: .destructive) { messages.removeAll() }
            Button("Cancel", role: .cancel) {}
        }
        .onAppear {
            isMuted = mutedThreads.split(separator: "|").contains { $0 == message.threadID }
            loadMessages()
        }
    }

    // MARK: Thread menu (⋯)
    private var threadMenu: some View {
        Menu {
            Button {
                #if canImport(UIKit)
                UIPasteboard.general.string = message.threadID
                #endif
            } label: {
                Label("Copy Contact Name", systemImage: "doc.on.doc")
            }

            Button {
                isMuted.toggle()
                var set = Set(mutedThreads.split(separator: "|").map(String.init))
                if isMuted { set.insert(message.threadID) } else { set.remove(message.threadID) }
                mutedThreads = set.joined(separator: "|")
            } label: {
                Label(isMuted ? "Unmute Notifications" : "Mute Notifications",
                      systemImage: isMuted ? "bell" : "bell.slash")
            }

            Divider()

            Button(role: .destructive) {
                showClearConfirm = true
            } label: {
                Label("Clear Chat", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(ResilixTheme.textPrimary)
                .rotationEffect(.degrees(90))
                .frame(minWidth: 32, minHeight: 32)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Chat options")
    }

    // MARK: Thread header — custom row with back button, avatar, name,
    // status pill, and a ⋯ menu. Rendered at the top of the VStack so the
    // avatar sits on the page background (no iOS nav-bar glass behind it).
    @Environment(\.dismiss) private var dismiss

    private var threadHeader: some View {
        HStack(spacing: 10) {
            // Back button (replaces the hidden nav bar's back chevron)
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                    .frame(width: 36, height: 36)
                    .background(
                        Circle()
                            .fill(Color.white.opacity(0.04))
                    )
            }
            .accessibilityLabel("Back")

            AvatarView(name: message.threadID,
                       size: 38,
                       online: online,
                       color: AvatarView.color(for: message.threadID))

            VStack(alignment: .leading, spacing: 4) {
                Text(message.threadID)
                    .font(ResilixTheme.font(17, .bold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                    .lineLimit(1)
                meshStatusPill
            }
            Spacer()
            threadMenu
        }
    }

    // Status pill under the name — matches the chats list badges
    private var meshStatusPill: some View {
        let route = (message.lastRoute ?? "Direct").lowercased()
        let kind: MeshStatusKind
        switch route {
        case "direct":  kind = .direct
        case "1 hop":   kind = .oneHop
        case "2 hops":  kind = .twoHops
        case "relayed": kind = .relayed
        case "waiting": kind = .waiting
        default:        kind = .direct
        }
        return Text(kind.label)
            .font(ResilixTheme.font(11, .heavy))
            .tracking(0.3)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(kind.color)
            .clipShape(Capsule())
    }

    private enum MeshStatusKind: String {
        case direct, oneHop, twoHops, relayed, waiting

        var label: String {
            switch self {
            case .direct:  return "Direct"
            case .oneHop:  return "1 Hop"
            case .twoHops: return "2 Hops"
            case .relayed: return "Relayed"
            case .waiting: return "Waiting"
            }
        }

        var color: Color {
            switch self {
            case .direct:  return ResilixTheme.brandCyan
            case .oneHop, .twoHops: return ResilixTheme.brandBlueGray
            case .relayed: return ResilixTheme.brandAmber
            case .waiting: return ResilixTheme.textTertiary
            }
        }
    }

    private var online: Bool { !message.threadID.lowercased().contains("&") }

    private var meshLabel: String {
        switch message.lastRoute {
        case "Direct": return "Direct"
        case "1 hop": return "1 Hop"
        case "2 hops": return "2 Hops"
        case "Relayed": return "Relayed"
        case "Waiting": return "Waiting"
        default: return "Direct"
        }
    }

    // MARK: Route bar
    private var routeBar: some View {
        HStack(spacing: ResilixTheme.space8) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(ResilixTheme.brandCyan)
            Text(routeSummary)
                .font(ResilixTheme.font(12, .regular))
                .foregroundStyle(ResilixTheme.textSecondary)
            Spacer()
        }
        .padding(.horizontal, ResilixTheme.space20)
        .padding(.vertical, ResilixTheme.space8)
        .background(ResilixTheme.brandTealSoft.opacity(0.6))
    }

    private var routeSummary: String {
        let hops = message.lastRoute.flatMap(Self.parseHops) ?? ["YOU", message.threadID]
        let arrowed = hops.joined(separator: " → ")
        return "Route: \(arrowed) · 2 hops · 340ms avg"
    }

    private static func parseHops(_ route: String) -> [String]? {
        // Try to split "A -> B -> C" style route
        let separators = ["->", "→"]
        for sep in separators {
            if route.contains(sep) {
                return route.components(separatedBy: sep).map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }
        return nil
    }

    // MARK: Mesh status bar
    private var meshStatusBar: some View {
        HStack(spacing: ResilixTheme.space8) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(ResilixTheme.brandAmber)
            Text("No internet · Routing via mesh")
                .font(ResilixTheme.font(11, .semibold))
                .foregroundStyle(ResilixTheme.brandAmber)
            Spacer()
        }
        .padding(.horizontal, ResilixTheme.space20)
        .padding(.vertical, ResilixTheme.space4)
        .background(ResilixTheme.brandAmber.opacity(0.08))
    }

    // MARK: Messages
    private var messagesScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: ResilixTheme.space8) {
                    ForEach(messages) { msg in
                        MessageBubble(message: msg)
                            .id(msg.id)
                    }
                }
                .padding(.horizontal, ResilixTheme.space16)
                .padding(.vertical, ResilixTheme.space12)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last?.id {
                    withAnimation(ResilixTheme.animationMedium) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: Input bar
    private var inputBar: some View {
        HStack(spacing: ResilixTheme.space8) {
            Button { showAttachmentOptions = true } label: {
                Image(systemName: "face.smiling")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(ResilixTheme.textTertiary)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Emoji")

            HStack {
                TextField("Message", text: $draft)
                    .focused($inputFocused)
                    .font(ResilixTheme.font(15, .regular))
                    .foregroundStyle(ResilixTheme.textPrimary)
                Spacer(minLength: 8)
                Button { showAttachmentOptions = true } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ResilixTheme.textTertiary)
                }
                .accessibilityLabel("Attach")
                Button { showCamera = true } label: {
                    Image(systemName: "camera")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(ResilixTheme.textTertiary)
                }
                .accessibilityLabel("Camera")
            }
            .padding(.horizontal, ResilixTheme.space12)
            .padding(.vertical, ResilixTheme.space8)
            .background(ResilixTheme.surfacePrimary)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(ResilixTheme.separator.opacity(0.5), lineWidth: 0.6))
            .shadow(color: Color.black.opacity(0.2), radius: 4, x: 0, y: 2)

            Button { showVoiceRecorder = true } label: {
                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(ResilixTheme.brandCyan)
                    .clipShape(Circle())
                    .shadow(color: ResilixTheme.cyanGlowStrong, radius: 6, x: 0, y: 0)
                    .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
            }
            .accessibilityLabel("Voice message")

            Button {
                send()
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(ResilixTheme.brandCyan)
                    .clipShape(Circle())
                    .shadow(color: ResilixTheme.cyanGlowStrong, radius: 6, x: 0, y: 0)
                    .shadow(color: Color.black.opacity(0.25), radius: 3, x: 0, y: 2)
            }
            .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.5 : 1)
            .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, ResilixTheme.space8)
        .padding(.vertical, ResilixTheme.space8)
        .background(ResilixTheme.backgroundPrimary)
        .confirmationDialog("Attach", isPresented: $showAttachmentOptions, titleVisibility: .visible) {
            Button("Photo Library") { showPhotoPicker = true }
            Button("Camera") { showCamera = true }
            Button("Cancel", role: .cancel) {}
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { image in
                // Handle camera photo
                sendImage(image)
            }
        }
        .photosPicker(isPresented: $showPhotoPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { _, newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    sendImage(image)
                }
            }
        }
        .sheet(isPresented: $showVoiceRecorder) {
            VoiceRecorderView { audioURL in
                // Send voice message
                sendVoiceMessage(audioURL)
            }
        }
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        let new = ThreadMessage(
            id: UUID().uuidString,
            text: text,
            fromMe: true,
            createdAt: Date(),
            delivered: true
        )
        messages.append(new)
        draft = ""
        Task { try? await app.messageService.send(text: text, to: message.destinationNodeID, from: app.nodeID) }
    }

    private func loadMessages() {
        let name = message.threadID
        if name == "Sarah K." {
            messages = [
                ThreadMessage(id: "m1", text: "Hey — mesh just connected! Are you okay?",
                              fromMe: false, createdAt: Date().addingTimeInterval(-360), delivered: true),
                ThreadMessage(id: "m2", text: "Yes! Lost power but the app works. Where are you?",
                              fromMe: true, createdAt: Date().addingTimeInterval(-300), delivered: true),
                ThreadMessage(id: "m3", text: "Community center on Main St, about 600m from you.",
                              fromMe: false, createdAt: Date().addingTimeInterval(-240), delivered: true),
                ThreadMessage(id: "m4", text: "I can see you in the mesh map. Heading your way.",
                              fromMe: true, createdAt: Date().addingTimeInterval(-180), delivered: true),
                ThreadMessage(id: "m5", text: "Are you safe? We're at the community shelter on Main St",
                              fromMe: false, createdAt: Date().addingTimeInterval(-120), delivered: true),
            ]
        } else {
            messages = [
                ThreadMessage(id: "m1", text: message.text,
                              fromMe: false, createdAt: message.createdAt, delivered: true)
            ]
        }
    }

    private func sendImage(_ image: UIImage) {
        let new = ThreadMessage(
            id: UUID().uuidString,
            text: "[Image]",
            fromMe: true,
            createdAt: Date(),
            delivered: true
        )
        messages.append(new)
        // In a real app, you'd upload the image and send a reference
        Task { try? await app.messageService.send(text: "[Image sent]", to: message.destinationNodeID, from: app.nodeID) }
    }

    private func sendVoiceMessage(_ audioURL: URL) {
        let new = ThreadMessage(
            id: UUID().uuidString,
            text: "[Voice message]",
            fromMe: true,
            createdAt: Date(),
            delivered: true
        )
        messages.append(new)
        Task { try? await app.messageService.send(text: "[Voice message sent]", to: message.destinationNodeID, from: app.nodeID) }
    }
}

// MARK: - ThreadMessage model
struct ThreadMessage: Identifiable, Equatable {
    let id: String
    let text: String
    let fromMe: Bool
    let createdAt: Date
    let delivered: Bool
}

// MARK: - Message bubble
struct MessageBubble: View {
    let message: ThreadMessage

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            if message.fromMe { Spacer(minLength: 60) }

            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .font(ResilixTheme.font(15, .regular))
                    .foregroundStyle(ResilixTheme.textPrimary)
                    .padding(.horizontal, ResilixTheme.space12)
                    .padding(.vertical, ResilixTheme.space10)
                    .background(
                        Group {
                            if message.fromMe {
                                LinearGradient(colors: [ResilixTheme.brandCyan.opacity(0.55), ResilixTheme.brandTealSoft.opacity(0.85)],
                                               startPoint: .topLeading, endPoint: .bottomTrailing)
                            } else {
                                ResilixTheme.surfaceSecondary
                            }
                        }
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
                    .shadow(color: message.fromMe ? ResilixTheme.cyanGlow : .clear, radius: 6, x: 0, y: 0)

                HStack(spacing: 4) {
                    Text(Self.timeFormatter.string(from: message.createdAt))
                        .font(ResilixTheme.font(10, .regular))
                        .foregroundStyle(ResilixTheme.textTertiary)
                    if message.fromMe && message.delivered {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(ResilixTheme.brandCyan)
                    }
                }
                .padding(.horizontal, 6)
            }
            .frame(maxWidth: 280, alignment: message.fromMe ? .trailing : .leading)

            if !message.fromMe { Spacer(minLength: 60) }
        }
    }
}

// MARK: - Camera Picker
struct CameraPicker: UIViewControllerRepresentable {
    let onImagePicked: (UIImage) -> Void
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(onImagePicked: onImagePicked)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImagePicked: (UIImage) -> Void
        init(onImagePicked: @escaping (UIImage) -> Void) { self.onImagePicked = onImagePicked }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { onImagePicked(image) }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { picker.dismiss(animated: true) }
    }
}

// MARK: - Voice Recorder
struct VoiceRecorderView: View {
    let onRecorded: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isRecording = false
    @State private var audioRecorder: AVAudioRecorder?
    @State private var recordingURL: URL?
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Image(systemName: isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                    .font(.system(size: 80))
                    .foregroundStyle(isRecording ? ResilixTheme.emergencyRed : ResilixTheme.brandCyan)
                    .symbolEffect(.pulse, isActive: isRecording)
                
                Text(isRecording ? "Recording..." : "Tap to record")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(ResilixTheme.textPrimary)
                
                if let url = recordingURL {
                    Text("Recorded: \(url.lastPathComponent)")
                        .font(.caption)
                        .foregroundStyle(ResilixTheme.textSecondary)
                }
                
                Button {
                    if isRecording { stopRecording() } else { startRecording() }
                } label: {
                    Text(isRecording ? "Stop" : "Start")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(isRecording ? ResilixTheme.emergencyRed : ResilixTheme.brandCyan)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 40)
            }
            .padding()
            .navigationTitle("Voice Message")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        if let url = recordingURL { onRecorded(url) }
                        dismiss()
                    }
                    .disabled(recordingURL == nil)
                }
            }
        }
        .onAppear { setupAudioSession() }
    }
    
    private func setupAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default)
        try? session.setActive(true)
    }
    
    private func startRecording() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let url = documents.appendingPathComponent("voice_\(Date().timeIntervalSince1970).m4a")
        recordingURL = url
        
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]
        
        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            isRecording = true
        } catch {
            print("Failed to start recording: \(error)")
        }
    }
    
    private func stopRecording() {
        audioRecorder?.stop()
        isRecording = false
    }
}

#Preview {
    NavigationStack {
        MessageThreadView(message: MeshMessage(
            id: "p", packetID: nil, threadID: "Sarah K.", sourceNodeID: "Sarah K.",
            destinationNodeID: "YOU", text: "Hey", createdAt: Date(), deliveryState: .delivered,
            expirySeconds: nil, lastRoute: "Direct", priority: .normal
        ))
        .environmentObject(ResilixAppModel())
    }
}
