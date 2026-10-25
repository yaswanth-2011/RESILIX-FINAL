import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var app: ResilixAppModel
    @State private var showComposer = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    
    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    ForEach(app.messageService.messages, id: \.id) { msg in
                        NavigationLink(destination: MessageThreadView(message: msg)) {
                            MessageRow(message: msg)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await app.messageService.delete(id: msg.id) }
                            } label: {
                                Label(L("Delete"), systemImage: "trash")
                            }
                        }
                    }
                    if app.messageService.messages.isEmpty {
                        EmptyStateView(
                            title: L("No messages"),
                            subtitle: L("Messages work without internet. Start a conversation."),
                            icon: "message"
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(ResilixTheme.bgPrimary)
                .refreshable {
                    await loadMessages()
                }
                .overlay {
                    if isLoading && app.messageService.messages.isEmpty {
                        LoadingStateView()
                    }
                }
                .alert(L("Error"), isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
                    Button(L("OK")) { errorMessage = nil }
                } message: { msg in
                    Text(msg)
                }
            }
            .navigationTitle("Messages")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showComposer = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel(Text(L("Compose new message")))
                }
            }
            .sheet(isPresented: $showComposer) { MessageComposerView() }
            .task {
                await loadMessages()
            }
        }
    }
    
    private func loadMessages() async {
        isLoading = true
        // Messages are loaded automatically by MessageService
        try? await Task.sleep(nanoseconds: 200_000_000)
        isLoading = false
    }
    
    struct MessageRow: View {
        let message: MeshMessage
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(message.threadID)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ResilixTheme.textPrimary)
                    Spacer()
                    DeliveryStateView(state: message.deliveryState)
                }
                Text(message.previewText)
                    .font(.subheadline)
                    .foregroundStyle(ResilixTheme.textSecondary)
                    .lineLimit(2)
                HStack {
                    Text(message.createdAt, style: .time)
                        .font(.caption2)
                        .foregroundStyle(ResilixTheme.textTertiary)
                    if let r = message.lastRoute {
                        Text("• " + r)
                            .font(.caption2)
                            .foregroundStyle(ResilixTheme.textTertiary)
                    }
                    if message.deliveryState == .relaying {
                        Text(L("• 2 hops"))
                            .font(.caption2)
                            .foregroundStyle(ResilixTheme.brandTeal)
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("messages.to") + " \(message.threadID), \(message.deliveryState.label)")
        }
    }
}
