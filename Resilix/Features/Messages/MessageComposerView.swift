import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

struct MessageComposerView: View {
    @EnvironmentObject var app: ResilixAppModel
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var destination = ""
    @State private var expiry: TimeInterval? = nil
    @State private var isSending = false
    @State private var sendError: String?
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showVoiceRecorder = false
    @State private var showFileImporter = false
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(L("messages.destination"))) {
                    Picker(L("To"), selection: $destination) {
                        Text(L("Broadcast")).tag("")
                        ForEach(app.meshController.peers) { peer in
                            Text(peer.displayName ?? peer.alias).tag(peer.id)
                        }
                    }
                    accessibilityLabel(Text(L("Message destination")))
                    
                    HStack {
                        Text(L("Reachability"))
                            .font(.caption)
                            .foregroundStyle(ResilixTheme.textSecondary)
                        Spacer()
                        Text(reachabilityText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ResilixTheme.brandTeal)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(L("messages.reachability") + ": \(reachabilityText)")
                }
                
                Section(header: Text(L("messages.new"))) {
                    TextField(L("Message"), text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        accessibilityLabel(Text(L("Message text")))

                    HStack(spacing: ResilixTheme.space12) {
                        Button { showVoiceRecorder = true } label: {
                            Label(L("Voice"), systemImage: "mic.fill")
                        }
                        accessibilityLabel(Text(L("Record a voice message")))

                        PhotosPicker(selection: $selectedPhoto, matching: .images) {
                            Label(L("Photo"), systemImage: "photo")
                        }
                        accessibilityLabel(Text(L("Attach a photo")))

                        Button { showFileImporter = true } label: {
                            Label(L("File"), systemImage: "paperclip")
                        }
                        accessibilityLabel(Text(L("Attach a file")))
                    }
                    
                    Picker(L("messages.expiry"), selection: $expiry) {
                        Text(L("messages.noExpiry")).tag(nil as TimeInterval?)
                        Text(L("5 minutes")).tag(300 as TimeInterval?)
                        Text(L("1 hour")).tag(3600 as TimeInterval?)
                    }
                    accessibilityLabel(Text(L("Message expiry")))
                }
            }
            .navigationTitle(L("messages.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L("sos.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        sendMessage()
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Text(L("messages.send"))
                        }
                    }
                    .disabled(text.isEmpty || isSending)
                    accessibilityLabel(Text(L("Send message")))
                }
            }
            .onChange(of: selectedPhoto) { _, item in
                Task { await sendPhoto(item) }
            }
            .fileImporter(isPresented: $showFileImporter,
                          allowedContentTypes: [.item],
                          allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { Task { await sendFile(url) } }
                case .failure:
                    sendError = L("The file could not be opened.")
                }
            }
            .sheet(isPresented: $showVoiceRecorder) {
                VoiceRecorderView { url in
                    Task { await sendVoice(url) }
                }
            }
            .alert(L("Error"), isPresented: .constant(sendError != nil), presenting: sendError) { _ in
                Button(L("OK")) { sendError = nil }
            } message: { msg in
                Text(msg)
            }
        }
    }
    
    /// Real reachability information taken from the routing table.
    private var reachabilityText: String {
        guard !destination.isEmpty else { return L("Broadcast") }
        if app.meshController.isConnected(to: destination) { return L("Direct") }
        if let route = app.meshController.routing.routes.first(where: { $0.destination == destination }) {
            return "\(route.hopCount) " + (route.hopCount == 1 ? L("ui.hop") : L("ui.hops"))
        }
        return L("No route yet — the message will be queued")
    }

    /// Sends a photo as a chunked attachment.
    private func sendPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
        await sendAttachment(data: data,
                             fileName: "photo-\(UUID().uuidString).jpg",
                             mimeType: "image/jpeg",
                             kind: .image)
    }

    /// Sends an arbitrary file as a chunked attachment.
    private func sendFile(_ url: URL) async {
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            await sendAttachment(data: data,
                                 fileName: "file-\(UUID().uuidString)-\(url.lastPathComponent)",
                                 mimeType: "application/octet-stream",
                                 kind: .file)
        } catch {
            sendError = error.localizedDescription
        }
    }

    /// Sends a recorded voice note.
    private func sendVoice(_ url: URL) async {
        do {
            let data = try Data(contentsOf: url)
            await sendAttachment(data: data,
                                 fileName: "voice-\(UUID().uuidString).m4a",
                                 mimeType: "audio/mp4",
                                 kind: .voice)
        } catch {
            sendError = error.localizedDescription
        }
    }

    /// Stores the payload locally and sends it through the mesh.
    private func sendAttachment(data: Data,
                                fileName: String,
                                mimeType: String,
                                kind: MessageKind) async {
        do {
            try await app.persistence.write(data, to: "\(ResilixConstants.mediaDirectoryName)/\(fileName)")
            let attachment = AttachmentDescriptor(fileName: fileName,
                                                 mimeType: mimeType,
                                                 byteCount: data.count,
                                                 localFileName: fileName,
                                                 sha256: PacketCrypto.sha256Hex(data))
            let sent = try await app.messageService.sendMedia(kind: kind,
                                                              attachment: attachment,
                                                              text: text.trimmingCharacters(in: .whitespacesAndNewlines),
                                                              to: destination,
                                                              from: app.nodeID)
            let url = app.persistence.baseURL
                .appendingPathComponent(ResilixConstants.mediaDirectoryName, isDirectory: true)
                .appendingPathComponent(fileName)
            try await app.transferService.send(fileURL: url,
                                               to: destination,
                                               messageID: sent.id,
                                               mimeType: mimeType)
            dismiss()
        } catch {
            sendError = error.localizedDescription
        }
    }
    
    private func sendMessage() {
        isSending = true
        Task {
            do {
                _ = try await app.messageService.send(text: text, to: destination, from: app.nodeID)
                dismiss()
            } catch {
                sendError = error.localizedDescription
            }
            isSending = false
        }
    }
}
