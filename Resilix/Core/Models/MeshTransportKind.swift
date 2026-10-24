import Foundation
enum MeshTransportKind: String, Codable, Sendable, CaseIterable {
    case bluetooth = "Bluetooth"
    case peerToPeerWiFi = "P2P Wi-Fi"
    case wifiAware = "Wi-Fi Aware"
    case mock = "Mock"
}
