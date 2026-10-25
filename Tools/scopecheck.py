#!/usr/bin/env python3
"""Names the compiler would reject because nothing declares them.

Two "cannot find X in scope" shapes are cheap to detect from source alone:

1. A type that is used but never declared — e.g. a view renamed or dropped
   during a refactor (`NearbyDeviceCard`, which shipped in the initial commit
   and vanished when `NearbyView` was rewritten).
2. A bare identifier used in a call or subscript position that is declared
   nowhere in the project — e.g. a helper called from a body after the type
   that used to own it was replaced.

Not covered: an identifier that is only *read* (never called), such as a
property that moved out of its type. Those still need a real compiler or a
scope-resolving AST pass, so this tool is a net, not a proof.

Known-by-the-SDK names (SwiftUI, MapKit, SceneKit, SQLite, …) are listed below
so the check only reports names the project itself must provide.

Usage:  python3 Tools/scopecheck.py [--verbose]
Exit code 0 when nothing was found.
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCES = [ROOT / "Resilix"] + ([ROOT / "ResilixTests"] if (ROOT / "ResilixTests").is_dir() else [])

# Framework / SDK symbols. Extend only with names that really come from an
# imported module; anything else belongs in the project.
SDK_TYPES = set("""
Array Dictionary Set String Substring Int Int8 Int16 Int32 Int64 UInt UInt8 UInt16 UInt32 UInt64 Double Float
Bool Character Data Date DateInterval UUID URL URLRequest URLResponse URLSession URLComponents URLQueryItem
NSObject NSString NSError NSNumber NSLock NSRecursiveLock NSRegularExpression NSCache NSValue ObjectIdentifier
NSPredicate NSSortDescriptor NSItemProvider NSUserActivity NSRange NSCoder
NotificationCenter Timer TimeInterval Result Optional ClosedRange Range Set
DispatchQueue DispatchGroup DispatchSemaphore DispatchTime DispatchWorkItem NFC
Task TaskGroup ThrowingTaskGroup TaskPriority Actor MainActor AnyCancellable AsyncStream AsyncThrowingStream
Text Image Label Button VStack HStack ZStack ScrollView List Form Section Toggle Picker Stepper Slider Link
NavigationStack NavigationSplitView NavigationLink NavigationView ProgressView Group EmptyView AnyView TupleView
ForEach GeometryReader GeometryProxy Divider Spacer LazyVStack LazyHStack LazyVGrid LazyHGrid Grid GridItem
Circle Rectangle RoundedRectangle Capsule Ellipse Path Shape AnyShape StrokeStyle LinearGradient RadialGradient
AngularGradient Color Gradient Animation Transaction withAnimation withCheckedContinuation
withCheckedThrowingContinuation withTaskGroup withThrowingTaskGroup
Menu DisclosureGroup SecureField TextField TextEditor ColorPicker ShareLink TabView Tab TabSection
ToolbarItem ToolbarItemGroup PhotosPicker PhotosPickerItem PhotosPickerSelectionBehavior
ObservableObject Published ObservedObject StateObject State Binding Environment EnvironmentObject EnvironmentValues
AppStorage ScenePhase OpenURL ViewModifier DynamicProperty ViewBuilder PreviewProvider
DragGesture LongPressGesture TapGesture MagnificationGesture RotationGesture SpatialTapGesture
Map Annotation Marker MapCamera MapCameraPosition MapPolyline MapScaleView MapContentBuilder
MKCoordinateRegion MKCoordinateSpan MKMapView MKPointAnnotation MKTileOverlay MKTileOverlayRenderer
MKPolyline MKPolylineRenderer MKMarkerAnnotationView MKAnnotationView MKOverlayRenderer MKMapSnapshotter
MKMapSnapshot MKMapRect MKMapPoint MKMapSize MKUserLocation MKClusterAnnotation MKLocalSearch MKLocalSearchRequest
MKLocalSearchCompletion MKLocalSearchCompleter
CLLocation CLLocationCoordinate2D CLLocationManager CLGeocoder CLAuthorizationStatus
AVAudioSession AVAudioRecorder AVAudioPlayer AVAudioApplication AVURLAsset AVPlayer AVPlayerItem
AVPlayerViewController AVAudioEngine AVAudioFormat AVAudioFile AVAudioPCMBuffer AVAudioPlayerNode
AVAudioRecorderDelegate AVAudioPlayerDelegate AVAssetExportSession AVAssetReader AVAssetWriter AVAssetWriterInput
AVCaptureSession AVCaptureDevice AVCaptureVideoPreviewLayer AVCapturePhotoOutput AVCaptureSessionPreset
CBCentralManager CBPeripheral CBPeripheralManager CBService CBUUID CBCharacteristic CBMutableService
CBMutableCharacteristic CBCentralManagerScanOptionAllowDuplicatesKey CBManagerState CBPeripheralState
NWBrowser NWListener NWConnection NWParameters NWEndpoint NWProtocolTCP NWProtocolUDP NWTXTRecord
NWBrowseDescriptor NWPathMonitor NWPath NWError NWConnection StateUpdateHandler
CryptoKit P256 Curve25519 AES GCM ChaChaPoly SHA256 SHA384 SHA512 HMAC SymmetricKey HKDF SecureEnclave
SecItemAdd SecItemCopyMatching SecItemDelete SecAccessControl SecRandomCopyBytes
UIColor UIFont UIImage UIView UIApplication UIDevice UIScreen UIPasteboard UIImagePickerController
UIViewController UIViewControllerRepresentable UIViewControllerRepresentableContext UIImagePickerControllerDelegate
UINavigationControllerDelegate UIActivityViewController UIDocumentPickerViewController UIDocumentInteractionController
UIImpactFeedbackGenerator UINotificationFeedbackGenerator UISelectionFeedbackGenerator UIGraphicsImageRenderer
UIBezierPath UIAlertController UIWindow UIWindowScene UIScene UISceneDelegate
UTType QLPreviewController
SCNScene SCNNode SCNView SCNCamera SCNLight SCNCylinder SCNSphere SCNVector3 SCNVector4 SCNMaterial SCNGeometry
CABasicAnimation CAMediaTimingFunction CALayer
FoundationModels SystemLanguageModel LanguageModelSession ModelContent Snapshot GenerationGuide
CMMotionManager CMDeviceMotion CMHeadphoneMotionManager
BGTaskScheduler BGProcessingTaskRequest BGAppRefreshTaskRequest
UNUserNotificationCenter UNNotificationRequest UNMutableNotificationContent
JSONEncoder JSONDecoder PropertyListEncoder PropertyListDecoder Codable Encodable Decodable
Calendar Locale TimeZone NumberFormatter DateFormatter ISO8601DateFormatter RelativeDateTimeFormatter
FileManager FileHandle InputStream OutputStream ProcessInfo Bundle Scanner Cache
Encodable Hashable Equatable Identifiable Sendable Comparable CustomStringConvertible
CGFloat CGPoint CGSize CGRect CGColor CGImage CIImage CIContext CIFilter
LocalizedStringKey LocalizationValue
SQLite3 OpaquePointer
XCTestCase XCTestExpectation XCTFail
XCTAssertEqual XCTAssertEqualWithAccuracy XCTAssertNotEqual XCTAssertTrue XCTAssertFalse XCTAssertNil
XCTAssertNotNil XCTAssertGreaterThan XCTAssertGreaterThanOrEqual XCTAssertLessThan XCTAssertThrowsError
XCTAssertNoThrow
LiteRTLM Engine EngineConfig ConversationConfig SamplerConfig Message
""".split())

# Bare lowercase globals: stdlib/Darwin functions, compiler directives, keywords.
SDK_FUNCTIONS = set("""
print debugPrint dump fatalError precondition preconditionFailure assertionFailure assert readLine
min max abs pow sqrt sin cos tan atan2 floor ceil round ceilf sqrtf fabs
zip stride swap repeatElement sequence numericCast withUnsafeBytes withUnsafePointer
canImport targetEnvironment available escaping nonisolated isolated autoclosure Sendable
unsafeBitCast type of super self nil true false try await return if else guard switch default for while
is as some any throw throws rethrows inout defer do catch break continue fallthrough import init deinit
subscript extension protocol class struct enum actor func var let static private public internal fileprivate
open override final lazy weak unowned mutating nonmutating dynamic indirect convenience required get set
willSet didSet associatedtype typealias operator precedencegroup
selector keyPath objc_main
sqlite3_open_v2 sqlite3_close sqlite3_prepare_v2 sqlite3_bind_int sqlite3_bind_text sqlite3_bind_blob
sqlite3_clear_bindings sqlite3_step sqlite3_column_blob sqlite3_column_bytes sqlite3_column_text
sqlite3_column_int sqlite3_finalize sqlite3_reset sqlite3_errmsg
sec_random_copy_bytes
withAnimation withCheckedContinuation withCheckedThrowingContinuation
withTaskGroup withThrowingTaskGroup withUnsafeBytes withUnsafePointer
draw
""".split())


def strip_comments_and_strings(text: str) -> str:
    out: list[str] = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                out.append(" ")
                i += 1
        elif c == "/" and i + 1 < n and text[i + 1] == "*":
            depth = 1
            out.append("  ")
            i += 2
            while i < n and depth:
                if text.startswith("/*", i):
                    depth += 1
                    out.append("  ")
                    i += 2
                elif text.startswith("*/", i):
                    depth -= 1
                    out.append("  ")
                    i += 2
                else:
                    out.append("\n" if text[i] == "\n" else " ")
                    i += 1
        elif text.startswith('"""', i):
            out.append("   ")
            i += 3
            end = text.find('"""', i)
            if end < 0:
                end = n
            out.append("".join("\n" if ch == "\n" else " " for ch in text[i:end]))
            i = end + 3
            out.append("   ")
        elif c == '"':
            out.append(" ")
            i += 1
            while i < n:
                if text[i] == "\\":
                    out.append("  ")
                    i += 2
                    continue
                if text[i] == '"':
                    out.append(" ")
                    i += 1
                    break
                out.append("\n" if text[i] == "\n" else " ")
                i += 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def main() -> int:
    verbose = "--verbose" in sys.argv
    files = sorted(p for root in SOURCES for p in root.rglob("*.swift"))
    clean = {p: strip_comments_and_strings(p.read_text()) for p in files}
    alltext = "\n".join(clean.values())

    declared_types = set(re.findall(r"\b(?:struct|class|enum|actor|protocol|typealias)\s+([A-Z]\w*)", alltext))

    used_types: dict[str, set[str]] = {}
    for p, src in clean.items():
        for m in re.finditer(r"(?<![.\w])([A-Z]\w{2,})\s*(?:<[^<>()]*>)?\s*\(", src):
            used_types.setdefault(m.group(1), set()).add(p.relative_to(ROOT).as_posix())

    unknown_types = {
        name: where for name, where in used_types.items()
        if name not in declared_types and name not in SDK_TYPES
    }

    declared_names = set()
    declared_names |= set(re.findall(r"\b(?:let|var)\s+([a-z_]\w*)", alltext))
    declared_names |= set(re.findall(r"\bfor\s+([a-z_]\w*)\b", alltext))
    declared_names |= set(re.findall(r"\bcase\s+([a-z_]\w*)\b", alltext))
    declared_names |= set(re.findall(r"\bfunc\s+([a-z_]\w*)", alltext))
    declared_names |= set(re.findall(r"[(,]\s*([a-z_]\w*)\s*:", alltext))
    declared_names |= set(re.findall(r"_\s+([a-z_]\w*)\s*:", alltext))
    declared_names |= set(re.findall(r"\b([a-z_]\w*)\s*:\s*\w", alltext))
    # external label followed by the internal parameter name: `withInfo info:`
    declared_names |= set(re.findall(r"\b[a-z_]\w*\s+([a-z_]\w*)\s*:", alltext))

    used_names: dict[str, set[str]] = {}
    for p, src in clean.items():
        for m in re.finditer(r"(?<![.\w])([a-z_]\w{2,})\s*[(\[]", src):
            used_names.setdefault(m.group(1), set()).add(p.relative_to(ROOT).as_posix())

    unknown_names = {
        name: where for name, where in used_names.items()
        if name not in declared_names and name not in SDK_FUNCTIONS
    }

    print(f"files scanned: {len(files)}")
    print(f"declared types: {len(declared_types)} · referenced types: {len(used_types)}")
    print(f"unknown types: {len(unknown_types)}")
    for name in sorted(unknown_types):
        print("  " + name + "  (" + ", ".join(sorted(unknown_types[name])[:3]) + ")")
    print(f"unknown identifiers: {len(unknown_names)}")
    for name in sorted(unknown_names):
        print("  " + name + "  (" + ", ".join(sorted(unknown_names[name])[:3]) + ")")
    if verbose:
        print("known SDK types:", len(SDK_TYPES), "· known globals:", len(SDK_FUNCTIONS))
    return 0 if not (unknown_types or unknown_names) else 1


if __name__ == "__main__":
    sys.exit(main())
