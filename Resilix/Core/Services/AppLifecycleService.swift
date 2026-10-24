import Foundation
#if canImport(UIKit)
import UIKit
#endif
import Combine

@MainActor
class AppLifecycleService: ObservableObject {
    @Published var isActive = true
    @Published var backgroundTime: Date?
    private var cancellables = Set<AnyCancellable>()
    private var meshController: MeshController?
    private var relayManager: RelayManager?
    
    func configure(meshController: MeshController, relayManager: RelayManager) {
        self.meshController = meshController
        self.relayManager = relayManager
        setupObservers()
    }
    
    private func setupObservers() {
#if canImport(UIKit)
        NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
            .sink { [weak self] _ in self?.onBackground() }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in self?.onForeground() }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: UIApplication.willTerminateNotification)
            .sink { [weak self] _ in self?.onTerminate() }
            .store(in: &cancellables)
#endif
    }
    
    func onLaunch() {
        isActive = true
    }
    
    func onForeground() {
        isActive = true
        backgroundTime = nil
        Task {
            // Restart mesh discovery if relay is enabled
            if relayManager?.isRelayActive == true {
                await meshController?.start()
            }
            // Process any queued packets that may have been persisted
            await meshController?.processQueuedPackets()
        }
    }
    
    func onBackground() {
        isActive = false
        backgroundTime = Date()
        Task {
            // Persist current state
            await relayManager?.persistState()
            // Stop active discovery to save battery (but keep listening if relay enabled)
            if relayManager?.isRelayActive != true {
                await meshController?.stop()
            }
        }
    }
    
    func onTerminate() {
        Task {
            await relayManager?.persistState()
            await meshController?.stop()
        }
    }
}
