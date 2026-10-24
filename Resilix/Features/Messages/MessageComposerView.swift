import SwiftUI

struct MessageComposerView: View {
    @EnvironmentObject var app: ResilixAppModel
    @Environment(\.dismiss) var dismiss
    @State private var text = ""
    @State private var destination = "C"
    @State private var expiry: TimeInterval? = nil
    @State private var isSending = false
    @State private var sendError: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(String(localized: "messages.destination"))) {
                    Picker("To", selection: $destination) {
                        Text("Node C (via relay)").tag("C")
                        Text("Relay B (direct)").tag("B")
                        Text("Broadcast").tag("")
                    }
                    .accessibilityLabel("Message destination")
                    
                    HStack {
                        Text("Reachability")
                            .font(.caption)
                            .foregroundStyle(ResilixTheme.textSecondary)
                        Spacer()
                        Text(reachabilityText)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(ResilixTheme.brandTeal)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Reachability: \(reachabilityText)")
                }
                
                Section(header: Text(String(localized: "messages.new"))) {
                    TextField("Message", text: $text, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("Message text")
                    
                    Picker(String(localized: "messages.expiry"), selection: $expiry) {
                        Text(String(localized: "messages.noExpiry")).tag(nil as TimeInterval?)
                        Text("5 minutes").tag(300 as TimeInterval?)
                        Text("1 hour").tag(3600 as TimeInterval?)
                    }
                    .accessibilityLabel("Message expiry")
                }
            }
            .navigationTitle(String(localized: "messages.new"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "sos.cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        sendMessage()
                    } label: {
                        if isSending {
                            ProgressView()
                        } else {
                            Text(String(localized: "messages.send"))
                        }
                    }
                    .disabled(text.isEmpty || isSending)
                    .accessibilityLabel("Send message")
                }
            }
            .alert("Error", isPresented: .constant(sendError != nil), presenting: sendError) { _ in
                Button("OK") { sendError = nil }
            } message: { msg in
                Text(msg)
            }
        }
    }
    
    private var reachabilityText: String {
        switch destination {
        case "C": return "Relay required • 2 hops"
        case "B": return "Direct"
        default: return "Broadcast"
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
