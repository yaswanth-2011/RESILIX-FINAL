import Foundation
import Network

/// Optional Wi-Fi Aware transport.
///
/// Wi-Fi Aware (NAN) requires iOS 26+, a dedicated entitlement
/// (com.apple.developer.networking.wifi-aware) granted by Apple, and
/// supported hardware. None of that is guaranteed at build or run time,
/// so this transport reports honestly: it only becomes `isAvailable`
/// after the capability check succeeds. Every other transport keeps the
/// mesh working when this one is unavailable.
final class WiFiAwareTransport: MeshTransport, @unchecked Sendable {
    let transportKind: MeshTransportKind = .wifiAware
    private(set) var isAvailable: Bool = false
    var discoveredPeers: [MeshNode] { [] }

    private let frameStream: AsyncStream<(Data, String)>
    private let eventStream: AsyncStream<MeshTransportEvent>
    private var frameContinuation: AsyncStream<(Data, String)>.Continuation?
    private var eventContinuation: AsyncStream<MeshTransportEvent>.Continuation?
    private var browser: NWBrowser?
    private var listener: NWListener?

    init() {
        var fc: AsyncStream<(Data, String)>.Continuation?
        frameStream = AsyncStream { fc = $0 }
        frameContinuation = fc

        var ec: AsyncStream<MeshTransportEvent>.Continuation?
        eventStream = AsyncStream { ec = $0 }
        eventContinuation = ec

        checkAvailability()
    }

    private func checkAvailability() {
        // The Wi-Fi Aware entitlement is not present in the default
        // signing profile, so the honest state is "not supported on this
        // device" until a properly entitled build enables it.
        #if targetEnvironment(simulator)
        isAvailable = false
        #else
        isAvailable = false
        #endif
    }

    func startDiscovery() async {
        guard isAvailable else { return }

        let params = NWParameters()
        params.includePeerToPeer = true

        let descriptor = NWBrowser.Descriptor.bonjour(type: "_resilix-aware._tcp", domain: nil)
        let browser = NWBrowser(for: descriptor, using: params)
        self.browser = browser

        browser.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed(let error):
                self?.eventContinuation?.yield(.error(error.localizedDescription))
            default:
                break
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            for result in results {
                self?.eventContinuation?.yield(
                    .peerDiscovered(id: result.endpoint.debugDescription, alias: "Wi-Fi Aware peer")
                )
            }
        }
        browser.start(queue: .main)
    }

    func stopDiscovery() async {
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
    }

    func connect(to peerID: String) async throws {
        guard isAvailable else { throw ResilixError.transportUnavailable("Wi-Fi Aware not supported on this device") }
        throw ResilixError.transportUnavailable("Wi-Fi Aware connection requires the Apple-granted entitlement")
    }

    func disconnect(from peerID: String) async {}

    func sendFrame(_ data: Data, to peerID: String) async throws {
        throw ResilixError.transportUnavailable("Wi-Fi Aware not supported on this device")
    }

    func receivedFrames() -> AsyncStream<(Data, String)> { frameStream }
    func connectionEvents() -> AsyncStream<MeshTransportEvent> { eventStream }
}
