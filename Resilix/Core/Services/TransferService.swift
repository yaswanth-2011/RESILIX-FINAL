import Foundation
import Combine

/// Chunked media transfer over the mesh.
///
/// Large files never travel inside a single packet. The protocol is:
///
/// 1. the sender sends a `mediaControl` packet with `action = offer`
///    (file name, size, chunk size, SHA-256 of the whole file);
/// 2. the receiver answers with `accept` (or `reject` when the file is too
///    big or the storage is full);
/// 3. the sender streams the file as `mediaChunk` packets;
/// 4. the receiver verifies the SHA-256 and answers with `complete`.
///
/// Every chunk carries the transfer id and its index, therefore out of
/// order delivery is detected and a missing chunk aborts the transfer.
@MainActor
final class TransferService: ObservableObject {
    @Published private(set) var transfers: [String: TransferState] = [:]
    @Published private(set) var lastErrorMessage: String?

    struct TransferState: Identifiable, Equatable {
        enum Status: String, Equatable {
            case offered
            case accepted
            case transferring
            case verifying
            case completed
            case rejected
            case cancelled
            case failed
        }

        var id: String
        var fileName: String
        var mimeType: String
        var byteCount: Int
        var chunkSize: Int
        var sha256: String?
        var messageID: String?
        var peerID: String
        var direction: String          // "outgoing" / "incoming"
        var status: Status
        var transferredBytes: Int
        var localFileName: String?
        var errorMessage: String?

        var progress: Double {
            guard byteCount > 0 else { return 0 }
            return min(1, Double(transferredBytes) / Double(byteCount))
        }
    }

    private let meshController: MeshController
    private let persistence = PersistenceController.shared
    private var incomingChunks: [String: [Int: Data]] = [:]

    init(meshController: MeshController) {
        self.meshController = meshController
    }

    // MARK: - Sending

    /// Sends a file to a peer.
    func send(fileURL: URL, to peerID: String, messageID: String, mimeType: String) async throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
        let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
        guard byteCount > 0 else { throw ResilixError.persistenceFailed(L("The file is empty")) }
        guard byteCount <= ResilixConstants.maxMediaBytes else {
            throw ResilixError.packetTooLarge
        }

        let transferID = UUID().uuidString
        // Keep a stable copy so that the chunks can be streamed afterwards.
        let staged = FileManager.default.temporaryDirectory
            .appendingPathComponent("outgoing-\(transferID)")
        try? FileManager.default.removeItem(at: staged)
        try FileManager.default.copyItem(at: fileURL, to: staged)
        let data = try Data(contentsOf: staged)
        let digest = PacketCrypto.sha256Hex(data)

        transfers[transferID] = TransferState(id: transferID,
                                              fileName: fileURL.lastPathComponent,
                                              mimeType: mimeType,
                                              byteCount: byteCount,
                                              chunkSize: ResilixConstants.mediaChunkSize,
                                              sha256: digest,
                                              messageID: messageID,
                                              peerID: peerID,
                                              direction: "outgoing",
                                              status: .offered,
                                              transferredBytes: 0,
                                              localFileName: nil,
                                              errorMessage: nil)

        let offer = MediaTransferControl(action: .offer,
                                         transferID: transferID,
                                         fileName: fileURL.lastPathComponent,
                                         mimeType: mimeType,
                                         byteCount: byteCount,
                                         chunkSize: ResilixConstants.mediaChunkSize,
                                         chunkIndex: 0,
                                         sha256: digest,
                                         messageID: messageID)
        let payload = try JSONEncoder().encode(offer)
        _ = try await meshController.sendPlainPacket(type: .mediaControl,
                                                    payload: payload,
                                                    destination: peerID,
                                                    priority: .high)
    }

    /// Streams the chunks of a prepared transfer.
    func streamChunks(transferID: String) async throws {
        guard var state = transfers[transferID] else { return }
        let fileName = state.fileName
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent("outgoing-\(transferID)")
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        let data = try Data(contentsOf: sourceURL)
        let chunkSize = state.chunkSize
        var index = 0
        var offset = 0
        while offset < data.count {
            let end = min(offset + chunkSize, data.count)
            let chunk = data.subdata(in: offset..<end)
            let framed = TransferService.frameChunk(transferID: transferID, index: index, chunk: chunk)
            _ = try await meshController.sendSecurePacket(type: .mediaChunk,
                                                         plaintext: framed,
                                                         destination: state.peerID,
                                                         priority: .high)
            offset = end
            index += 1
            state.transferredBytes = offset
            state.status = .transferring
            transfers[transferID] = state
        }
        let complete = MediaTransferControl(action: .complete,
                                            transferID: transferID,
                                            fileName: fileName,
                                            mimeType: state.mimeType,
                                            byteCount: state.byteCount,
                                            chunkSize: chunkSize,
                                            chunkIndex: index,
                                            sha256: state.sha256,
                                            messageID: state.messageID)
        let payload = try JSONEncoder().encode(complete)
        _ = try await meshController.sendPlainPacket(type: .mediaControl,
                                                    payload: payload,
                                                    destination: state.peerID,
                                                    priority: .high)
        state.status = .completed
        transfers[transferID] = state
    }

    func cancel(transferID: String) async {
        guard let state = transfers[transferID] else { return }
        let control = MediaTransferControl(action: .cancel,
                                           transferID: transferID,
                                           fileName: state.fileName,
                                           mimeType: state.mimeType,
                                           byteCount: state.byteCount,
                                           chunkSize: state.chunkSize,
                                           chunkIndex: 0,
                                           sha256: state.sha256,
                                           messageID: state.messageID)
        if let payload = try? JSONEncoder().encode(control) {
            _ = try? await meshController.sendPlainPacket(type: .mediaControl,
                                                         payload: payload,
                                                         destination: state.peerID,
                                                         priority: .normal)
        }
        var updated = state
        updated.status = .cancelled
        transfers[transferID] = updated
        incomingChunks.removeValue(forKey: transferID)
    }

    // MARK: - Receiving

    /// Handles an incoming control packet.
    func handle(control: MediaTransferControl, from peerID: String) async {
        switch control.action {
        case .offer:
            await handleOffer(control, from: peerID)
        case .accept:
            if var state = transfers[control.transferID] {
                state.status = .accepted
                transfers[control.transferID] = state
            }
            // The peer is ready: stream the chunks.
            Task { try? await streamChunks(transferID: control.transferID) }
        case .reject:
            if var state = transfers[control.transferID] {
                state.status = .rejected
                state.errorMessage = L("The peer refused the transfer.")
                transfers[control.transferID] = state
            }
        case .cancel:
            if var state = transfers[control.transferID] {
                state.status = .cancelled
                transfers[control.transferID] = state
            }
            incomingChunks.removeValue(forKey: control.transferID)
        case .complete:
            if var state = transfers[control.transferID] {
                state.status = .verifying
                transfers[control.transferID] = state
            }
        }
    }

    private func handleOffer(_ control: MediaTransferControl, from peerID: String) async {
        guard control.byteCount > 0, control.byteCount <= ResilixConstants.maxMediaBytes else {
            let reject = MediaTransferControl(action: .reject,
                                              transferID: control.transferID,
                                              fileName: control.fileName,
                                              mimeType: control.mimeType,
                                              byteCount: control.byteCount,
                                              chunkSize: control.chunkSize,
                                              chunkIndex: 0,
                                              sha256: control.sha256,
                                              messageID: control.messageID)
            if let payload = try? JSONEncoder().encode(reject) {
                _ = try? await meshController.sendPlainPacket(type: .mediaControl,
                                                             payload: payload,
                                                             destination: peerID,
                                                             priority: .normal)
            }
            return
        }

        transfers[control.transferID] = TransferState(id: control.transferID,
                                                      fileName: control.fileName,
                                                      mimeType: control.mimeType,
                                                      byteCount: control.byteCount,
                                                      chunkSize: control.chunkSize,
                                                      sha256: control.sha256,
                                                      messageID: control.messageID,
                                                      peerID: peerID,
                                                      direction: "incoming",
                                                      status: .accepted,
                                                      transferredBytes: 0,
                                                      localFileName: nil,
                                                      errorMessage: nil)
        incomingChunks[control.transferID] = [:]

        let accept = MediaTransferControl(action: .accept,
                                           transferID: control.transferID,
                                           fileName: control.fileName,
                                           mimeType: control.mimeType,
                                           byteCount: control.byteCount,
                                           chunkSize: control.chunkSize,
                                           chunkIndex: 0,
                                           sha256: control.sha256,
                                           messageID: control.messageID)
        if let payload = try? JSONEncoder().encode(accept) {
            _ = try? await meshController.sendPlainPacket(type: .mediaControl,
                                                         payload: payload,
                                                         destination: peerID,
                                                         priority: .normal)
        }
    }

    /// Handles an incoming chunk and finalises the transfer when complete.
    func handleChunk(transferID: String, index: Int, chunk: Data) async {
        guard var state = transfers[transferID] else { return }
        var chunks = incomingChunks[transferID] ?? [:]
        chunks[index] = chunk
        incomingChunks[transferID] = chunks
        state.transferredBytes = chunks.values.reduce(0) { $0 + $1.count }
        state.status = .transferring
        transfers[transferID] = state

        let expectedChunks = Int(ceil(Double(state.byteCount) / Double(max(1, state.chunkSize))))
        guard chunks.count >= expectedChunks else { return }
        await finalize(transferID: transferID)
    }

    /// Verifies the checksum and writes the file to the media directory.
    func finalize(transferID: String) async {
        guard var state = transfers[transferID] else { return }
        guard let chunks = incomingChunks[transferID] else { return }
        let expectedChunks = Int(ceil(Double(state.byteCount) / Double(max(1, state.chunkSize))))
        guard chunks.count >= expectedChunks else { return }

        var assembled = Data()
        for index in 0..<expectedChunks {
            guard let chunk = chunks[index] else {
                var failed = state
                failed.status = .failed
                failed.errorMessage = L("A chunk of the transfer is missing.")
                transfers[transferID] = failed
                incomingChunks.removeValue(forKey: transferID)
                return
            }
            assembled.append(chunk)
        }

        if let expected = state.sha256, !expected.isEmpty {
            let digest = PacketCrypto.sha256Hex(assembled)
            guard digest == expected else {
                var failed = state
                failed.status = .failed
                failed.errorMessage = L("The received file is corrupted (checksum mismatch).")
                transfers[transferID] = failed
                incomingChunks.removeValue(forKey: transferID)
                return
            }
        }

        let fileName = "recv-\(UUID().uuidString)-\(state.fileName)"
        let relative = "\(ResilixConstants.mediaDirectoryName)/\(fileName)"
        do {
            try await persistence.write(assembled, to: relative)
            state.localFileName = fileName
            state.status = .completed
            state.transferredBytes = assembled.count
            transfers[transferID] = state
            incomingChunks.removeValue(forKey: transferID)
            await persistence.enforceStorageLimit(named: ResilixConstants.mediaDirectoryName,
                                                 limitBytes: ResilixConstants.maxMediaBytes)
        } catch {
            var failed = state
            failed.status = .failed
            failed.errorMessage = L("The file could not be stored.")
            transfers[transferID] = failed
            incomingChunks.removeValue(forKey: transferID)
        }
    }

    /// URL of a received file inside the media directory.
    func localURL(for fileName: String) -> URL {
        persistence.baseURL
            .appendingPathComponent(ResilixConstants.mediaDirectoryName, isDirectory: true)
            .appendingPathComponent(fileName)
    }

    // MARK: - Chunk framing

    /// Binary framing of a chunk: transfer id (36 bytes) + index (4 bytes).
    nonisolated static func frameChunk(transferID: String, index: Int, chunk: Data) -> Data {
        var data = Data(transferID.utf8)
        let value = UInt32(index)
        data.append(UInt8((value >> 24) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8(value & 0xFF))
        data.append(chunk)
        return data
    }

    /// Parses the binary framing of a chunk.
    nonisolated static func parseChunk(_ data: Data) -> (transferID: String, index: Int, chunk: Data)? {
        guard data.count >= 40 else { return nil }
        let idEnd = data.index(data.startIndex, offsetBy: 36)
        guard let transferID = String(data: data[data.startIndex..<idEnd], encoding: .utf8) else { return nil }
        let bytes = [UInt8](data[idEnd..<min(idEnd + 4, data.endIndex)])
        guard bytes.count == 4 else { return nil }
        let index = Int((UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16) | (UInt32(bytes[2]) << 8) | UInt32(bytes[3]))
        let chunkStart = data.index(idEnd, offsetBy: 4)
        return (transferID, index, Data(data[chunkStart...]))
    }
}
