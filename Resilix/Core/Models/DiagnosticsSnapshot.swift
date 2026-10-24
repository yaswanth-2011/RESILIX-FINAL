import Foundation

struct DiagnosticsSnapshot: Sendable, Equatable {
    var timestamp: Date
    var bluetoothState: String
    var p2pWiFiState: String
    var wifiAwareState: String
    var connectedCount: Int
    var discoveredCount: Int
    var routeCount: Int
    var queueCount: Int
    var forwardedCount: Int
    var droppedDuplicates: Int
    var expiredCount: Int
    var relayActive: Bool
    var protocolVersion: UInt8
    var persistenceStatus: String
    var permissionStatus: String
    var lastTransportEvent: String?
    var isDemo: Bool

    var debugDescription: String {
        """
        Resilix Diagnostics — \(timestamp.formatted(date: .abbreviated, time: .standard))
        Bluetooth: \(bluetoothState) • P2P Wi-Fi: \(p2pWiFiState) • Wi-Fi Aware: \(wifiAwareState)
        Peers: connected \(connectedCount), discovered \(discoveredCount), routes \(routeCount)
        Queue: \(queueCount) • Forwarded: \(forwardedCount) • Dropped dups: \(droppedDuplicates) • Expired: \(expiredCount)
        Relay: \(relayActive ? "Active" : "Inactive") • Protocol v\(protocolVersion) • Persistence: \(persistenceStatus) • Permissions: \(permissionStatus)
        Last event: \(lastTransportEvent ?? "—") • Demo: \(isDemo ? "Yes" : "No")
        """
    }
}
