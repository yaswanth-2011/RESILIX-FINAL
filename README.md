# Resilix — Survival & Resilience Mesh

Resilix is a **phone-only offline mesh messenger** for emergencies. Phones relay packets multi-hop (A → B → C) without internet, cellular, or external hardware.

## Architecture
- **Phone-only transports**: Bluetooth (CoreBluetooth) + Peer-to-Peer Wi-Fi (Network.framework via NWBrowser/NWListener). Wi-Fi Aware is optional and availability-checked.
- **No LoRa**: iPhones have no built-in LoRa radio; no external accessory required.
- **Application-layer forwarding**: `MeshRoutingEngine` selects next hops transport-agnostically; `RelayManager` queues/flood-controls; `DeduplicationStore` prevents loops.
- **Security**: CryptoKit AES-GCM end-to-end for private chat; relays forward ciphertext; Keychain for identity key.

## A → B → C Relay
Phone B verifies packet metadata (version, TTL, expiry, integrity), checks deduplication, decrements TTL, and forwards toward C. Demo Mode simulates this on a single simulator.

## Demo Mode
Enable in Profile → Demo Mode (DEBUG builds). Shows 3 simulated nodes (Source, Relay, Destination), a 2-hop route, and a “Need help at the north shelter” packet flowing B→C with ack returning. Demo uses `MockMeshTransport` feeding the same `MeshController` pipeline. A “Demo” badge marks simulated values.

## Replacing the Logo
Drop your logo PDFs into:
- `Resilix/Resources/Assets.xcassets/ResilixLogoPlaceholder.imageset/logo-placeholder.pdf`
- `Resilix/Resources/Assets.xcassets/ResilixMarkPlaceholder.imageset/mark-placeholder.pdf`
No code changes needed — `LogoView.swift` loads `ResilixLogoPlaceholder` with SF Symbol fallback.

## Building
1. Open `Resilix.xcodeproj` in Xcode 15+.
2. Select team in Signing & Capabilities.
3. Deployment target iOS 17.0 — builds and runs on iOS 17 through iOS 27 beta (Wi-Fi Aware availability-checked for iOS 26+ / 27). Tested for Xcode 15, 16, and Xcode 26/27 beta.
4. Build & run on simulator (Demo Mode works) or two+ iPhones for real mesh.

## Permissions
- Bluetooth (`NSBluetoothAlwaysUsageDescription`)
- Local Network (`NSLocalNetworkUsageDescription`, Bonjour `_resilix._tcp`)
- Location (When In Use) for SOS/map — requested contextually, not at launch.

## Physical Device Testing
- 2 iPhones: direct chat.
- 3 iPhones in line (A—B—C, A and C out of direct range): verify B relays.
- Test SOS, ack, peer disconnect, TTL expiry, queue saturation, permission denials, Wi-Fi Aware unsupported path, foreground/background resume.
- Simulator: only Demo Mode; real transports need devices.

## Folder Structure
```
Resilix/Core/{Theme,Models,Networking,Routing,Security,Persistence,Services,Utilities}
Resilix/Features/{Home,Mesh,Messages,Map,Assist,Profile,CommandCenter,SOS}
Resilix/SharedUI
Resilix/Resources
ResilixTests
```

## Privacy & Security
- No cloud backend for mesh.
- Relays see only routing metadata (IDs, sizes) not plaintext.
- Location shared only with consent, minimal precision.
- Map reports: “Community reported” until verified; stale warnings.
- Prototype — no formal certification, standard primitives only.

## Limitations
- iOS suspends background networking; foreground is reliable relay. Background modes are honest (bluetooth-central/peripheral) and `AppLifecycleService` restores queues on foreground.
- Wi-Fi Aware requires entitlement + supported device; app degrades gracefully.
- P2P Wi-Fi performance varies by device/iOS.

## Known LoRa Statement
This project **does not contain LoRa**, does not require LoRa hardware, and does not claim iPhones have LoRa radios.

## License
Prototype — internal use.
