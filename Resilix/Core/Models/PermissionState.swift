import Foundation
enum PermissionState: String, Sendable {
    case notDetermined, authorized, denied, restricted, unsupported
    var label: String { rawValue }
}
