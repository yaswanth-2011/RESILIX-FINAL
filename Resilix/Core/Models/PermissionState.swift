import Foundation
enum PermissionState: String, Sendable {
    case notDetermined, authorized, denied, restricted, unsupported
    var label: String {
        switch self {
        case .notDetermined: return L("permission.notDetermined")
        case .authorized: return L("permission.authorized")
        case .denied: return L("permission.denied")
        case .restricted: return L("permission.restricted")
        case .unsupported: return L("permission.unsupported")
        }
    }
}
