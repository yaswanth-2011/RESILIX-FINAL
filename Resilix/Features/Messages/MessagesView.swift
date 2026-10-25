import SwiftUI

struct MessagesView: View {
    @EnvironmentObject var app: ResilixAppModel
    @State private var showComposer = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var isEditMode = false
    @State private var threadsToDelete: Set<String> = []
    
    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    ForEach(app.messageService.conversations, id: \.self) { threadID in
                        let threadMessages = app.messageService.messages(in: threadID)
                        let latest = threadMessages.last
                        
                        NavigationLink(destination: MessageThreadView(message: latest ?? MeshMessage(
                            id: threadID, packetID: nil, threadID: threadID, sourceNodeID: "",
                            destinationNodeID: "", text: "", createdAt: Date(), deliveryState: .queued,
                            expirySeconds: nil, lastRoute: nil, priority: .normal
                        ))) {
                            MessageRow(threadID: threadID, message: latest)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                Task { await app.messageService.deleteThread(threadID) }
                            } label: {
                                Label(L("Delete"), systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                Task { await app.messageService.deleteThread(threadID) }
                            } label: {
                                Label(L("Delete"), systemImage: "trash")
                            }
                        }
                    }
                    
                    if app.messageService.conversations.isEmpty {
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
                    if isLoading && app.messageService.conversations.isEmpty {
                        LoadingStateView()
                    }
                }
                .alert(L("Error"), isPresented: .constant(errorMessage != nil), presenting: errorMessage) { _ in
                    Button(L("OK")) { errorMessage = nil }
                } message: { msg in
                    Text(msg)
                }
            }
            .navigationTitle("Chats")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showComposer = true } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel(Text(L("Compose new message")))
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        isEditMode.toggle()
                        if !isEditMode { threadsToDelete.removeAll() }
                    } label: {
                        Image(systemName: isEditMode ? "checkmark.circle.fill" : "pencil")
                            .foregroundStyle(isEditMode ? ResilixTheme.brandCyan : ResilixTheme.textPrimary)
                    }
                    .accessibilityLabel(Text(isEditMode ? L("Done") : L("Edit")))
                }
                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditMode {
                        Button {
                            Task { await deleteSelectedThreads() }
                            isEditMode = false
                            threadsToDelete.removeAll()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .accessibilityLabel(Text(L("Delete selected")))
                    }
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
        try? await Task.sleep(nanoseconds: 200_000_000)
        isLoading = false
    }
    
    private func deleteSelectedThreads() async {
        for threadID in threadsToDelete {
            await app.messageService.deleteThread(threadID)
        }
    }
    
    struct MessageRow: View {
        let threadID: String
        let message: MeshMessage?
        
        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(threadID)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(ResilixTheme.textPrimary)
                    Spacer()
                    if let msg = message {
                        DeliveryStateView(state: msg.deliveryState)
                    }
                }
                if let msg = message {
                    Text(msg.previewText)
                        .font(.subheadline)
                        .foregroundStyle(ResilixTheme.textSecondary)
                        .lineLimit(2)
                    HStack {
                        Text(msg.createdAt, style: .time)
                            .font(.caption2)
                            .foregroundStyle(ResilixTheme.textTertiary)
                        if let r = msg.lastRoute {
                            Text("• " + r)
                                .font(.caption2)
                                .foregroundStyle(ResilixTheme.textTertiary)
                        }
                        if msg.deliveryState == .relaying {
                            Text(L("• 2 hops"))
                                .font(.caption2)
                                .foregroundStyle(ResilixTheme.brandTeal)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(L("messages.to") + " " + threadID)
        }
    }
}
