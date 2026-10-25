#!/usr/bin/env python3
"""Give every enum whose raw value is displayed in the interface a localized
`label`, and use it at the display sites.

The raw values stay untouched because they are the persisted representation
(`appearance`, `ai_settings.json`, …).
"""
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[2]

EDITS = [
    # ------------------------------------------------------------ map styles
    ("Resilix/Features/Map/SurvivalMapView.swift",
     """    case threeD    = "3D"
    var id: String { rawValue }
""",
     """    case threeD    = "3D"
    var id: String { rawValue }

    /// Localized name shown in the layer sheet and the style badge.
    var label: String {
        switch self {
        case .standard:  return L("map.style.standard")
        case .hybrid:    return L("map.style.hybrid")
        case .satellite: return L("map.style.satellite")
        case .muted:     return L("map.style.muted")
        case .transit:   return L("map.style.transit")
        case .threeD:    return L("map.style.threeD")
        }
    }
""", 1),
    ("Resilix/Features/Map/SurvivalMapView.swift",
     "                Text(f.rawValue).tag(f)",
     "                Text(f.label).tag(f)", 1),
    ("Resilix/Features/Map/SurvivalMapView.swift",
     "                        title: option.rawValue,",
     "                        title: option.label,", 1),
    ("Resilix/Features/Map/SurvivalMapView.swift",
     "                Text(currentStyle.rawValue)",
     "                Text(currentStyle.label)", 1),
    ("Resilix/Features/Map/SurvivalMapView.swift",
     """        case cinematic = "Cinematic"
        var id: String { rawValue }
""",
     """        case cinematic = "Cinematic"
        var id: String { rawValue }

        /// Localized name shown in the 3D mode picker.
        var label: String {
            switch self {
            case .off:       return L("map.mode.off")
            case .tilted:    return L("map.mode.tilted")
            case .cinematic: return L("map.mode.cinematic")
            }
        }
""", 1),
    ("Resilix/Features/Map/SurvivalMapView.swift",
     "                        Text(m.rawValue).tag(m)",
     "                        Text(m.label).tag(m)", 1),
    ("Resilix/Features/Map/SurvivalMapView.swift",
     """        case routes = "Routes"
        var id: String { rawValue }
""",
     """        case routes = "Routes"
        var id: String { rawValue }

        /// Localized name shown in the segmented map filter.
        var label: String {
            switch self {
            case .all:      return L("map.all")
            case .devices:  return L("map.filter.devices")
            case .shelters: return L("map.filter.shelters")
            case .routes:   return L("map.filter.routes")
            }
        }
""", 1),
    # -------------------------------------------------------------- settings
    ("Resilix/Features/Profile/SettingsView.swift",
     """    enum Appearance: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
        var id: String { rawValue }
    }
""",
     """    enum Appearance: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"
        var id: String { rawValue }

        /// Localized name shown in the appearance dialog.
        var label: String {
            switch self {
            case .system: return L("settings.system")
            case .light:  return L("settings.light")
            case .dark:   return L("settings.dark")
            }
        }
    }
""", 1),
    ("Resilix/Features/Profile/SettingsView.swift",
     "                Button(option.rawValue) { appearance = option.rawValue }",
     "                Button(option.label) { appearance = option.rawValue }", 1),
    ("Resilix/Features/Profile/SettingsView.swift",
     "                            SettingsActionRow(icon: \"moon.circle.fill\", title: L(\"Appearance\"), value: appearance) {",
     "                            SettingsActionRow(icon: \"moon.circle.fill\", title: L(\"Appearance\"), value: Appearance(rawValue: appearance)?.label ?? appearance) {", 1),
    ("Resilix/Features/Profile/SettingsView.swift",
     """        case urdu = "Urdu"
        var id: String { rawValue }
    }
""",
     """        case urdu = "Urdu"
        var id: String { rawValue }

        /// Native name of the language, shown in the language picker.
        var label: String {
            switch self {
            case .english:  return L("language.english")
            case .hindi:    return L("language.hindi")
            case .telugu:   return L("language.telugu")
            case .tamil:    return L("language.tamil")
            case .kannada:  return L("language.kannada")
            case .malayalam: return L("language.malayalam")
            case .marathi:  return L("language.marathi")
            case .bengali:  return L("language.bengali")
            case .gujarati: return L("language.gujarati")
            case .punjabi:  return L("language.punjabi")
            case .urdu:     return L("language.urdu")
            }
        }
    }
""", 1),
    ("Resilix/Features/Profile/SettingsView.swift",
     "                                    Text(lang.rawValue)",
     "                                    Text(lang.label)", 1),
    ("Resilix/Features/Profile/SettingsView.swift",
     """        case .ready: return "Ready"
        case .notInstalled: return L("Not installed")
        case .runtimeUnavailable: return L("No runtime")
        case .unusable: return "Unusable"
""",
     """        case .ready: return L("Ready")
        case .notInstalled: return L("Not installed")
        case .runtimeUnavailable: return L("No runtime")
        case .unusable: return L("Unusable")
""", 1),
    # ----------------------------------------------------------- assist view
    ("Resilix/Features/Assist/AssistView.swift",
     """    enum ResponseLength: String, CaseIterable, Identifiable, Codable {
        case concise  = "Concise"
        case balanced = "Balanced"
        case detailed = "Detailed"
        var id: String { rawValue }
    }
""",
     """    enum ResponseLength: String, CaseIterable, Identifiable, Codable {
        case concise  = "Concise"
        case balanced = "Balanced"
        case detailed = "Detailed"
        var id: String { rawValue }

        /// Localized name shown in the response length picker.
        var label: String {
            switch self {
            case .concise:  return L("ai.responseLength.concise")
            case .balanced: return L("ai.responseLength.balanced")
            case .detailed: return L("ai.responseLength.detailed")
            }
        }
    }
""", 1),
    ("Resilix/Features/Assist/AssistView.swift",
     """    enum Tone: String, CaseIterable, Identifiable, Codable {
        case friendly    = "Friendly"
        case professional = "Professional"
        case empathetic  = "Empathetic"
        var id: String { rawValue }
    }
""",
     """    enum Tone: String, CaseIterable, Identifiable, Codable {
        case friendly    = "Friendly"
        case professional = "Professional"
        case empathetic  = "Empathetic"
        var id: String { rawValue }

        /// Localized name shown in the tone picker.
        var label: String {
            switch self {
            case .friendly:     return L("ai.tone.friendly")
            case .professional: return L("ai.tone.professional")
            case .empathetic:   return L("ai.tone.empathetic")
            }
        }
    }
""", 1),
    ("Resilix/Features/Assist/AssistView.swift",
     """    enum Language: String, CaseIterable, Identifiable, Codable {
        case english = "English"
        case spanish = "Spanish"
        case french  = "French"
        case german  = "German"
        case auto    = "Auto-detect"
        var id: String { rawValue }
    }
""",
     """    enum Language: String, CaseIterable, Identifiable, Codable {
        case english = "English"
        case spanish = "Spanish"
        case french  = "French"
        case german  = "German"
        case auto    = "Auto-detect"
        var id: String { rawValue }

        /// Localized name of the language the assistant answers in.
        var label: String {
            switch self {
            case .english: return L("ai.language.english")
            case .spanish: return L("ai.language.spanish")
            case .french:  return L("ai.language.french")
            case .german:  return L("ai.language.german")
            case .auto:    return L("ai.language.auto")
            }
        }
    }
""", 1),
    ("Resilix/Features/Assist/AssistView.swift",
     "                                            Text(len.rawValue)",
     "                                            Text(len.label)", 1),
    ("Resilix/Features/Assist/AssistView.swift",
     "                                            Text(t.rawValue)",
     "                                            Text(t.label)", 1),
    ("Resilix/Features/Assist/AssistView.swift",
     "                    Button(lang.rawValue) { selection = lang }",
     "                    Button(lang.label) { selection = lang }", 1),
    ("Resilix/Features/Assist/AssistView.swift",
     "                    Text(selection.rawValue)",
     "                    Text(selection.label)", 1),
    ("Resilix/Features/Assist/AssistView.swift",
     """        case .ready:
            return "\\(model.displayName) · On-device"
""",
     """        case .ready:
            return String(format: L("%@ · On-device"), model.displayName)
""", 1),
    ("Resilix/Features/Assist/AssistView.swift",
     """        case .unusable:
            return "\\(model.displayName) · Unusable"
""",
     """        case .unusable:
            return String(format: L("%@ · Unusable"), model.displayName)
""", 1),
    # ------------------------------------------------------------ home view
    ("Resilix/Features/Home/HomeView.swift",
     """        case 3: return "Strong"
        case 2: return "Good"
        case 1: return "Weak"
""",
     """        case 3: return L("signal.strong")
        case 2: return L("signal.good")
        case 1: return L("signal.weak")
""", 1),
    # ---------------------------------------------------------- message views
    ("Resilix/Features/Messages/MessageComposerView.swift",
     """        guard !destination.isEmpty else { return "Broadcast" }
        if app.meshController.isConnected(to: destination) { return "Direct" }
        if let route = app.meshController.routing.routes.first(where: { $0.destination == destination }) {
            return "\\(route.hopCount) hop" + (route.hopCount == 1 ? "" : "s")
        }
""",
     """        guard !destination.isEmpty else { return L("Broadcast") }
        if app.meshController.isConnected(to: destination) { return L("Direct") }
        if let route = app.meshController.routing.routes.first(where: { $0.destination == destination }) {
            return "\\(route.hopCount) " + (route.hopCount == 1 ? L("ui.hop") : L("ui.hops"))
        }
""", 1),
    ("Resilix/Features/Messages/MessageThreadView.swift",
     """        let arrowed = hops.joined(separator: " → ")
        return "Route: \\(arrowed) · 2 hops · 340ms avg"
""",
     """        let arrowed = hops.joined(separator: " → ")
        let hopWord = hops.count == 1 ? L("ui.hop") : L("ui.hops")
        return L("Route") + ": " + arrowed + " · " + String(hops.count) + " " + hopWord
""", 1),
    # -------------------------------------------------------------- sos view
    ("Resilix/Features/SOS/SOSView.swift",
     "                        Text(active.category.rawValue)",
     "                        Text(active.category.label)", 1),
    # ------------------------------------------------------- command center
    ("Resilix/Features/CommandCenter/IncidentDetailView.swift",
     "                    Text(incident.status.rawValue.capitalized)",
     "                    Text(incident.status.label)", 1),
    # ------------------------------------------------------------ permissions
    ("Resilix/Features/Profile/PermissionStatusView.swift",
     "                    Text(state.rawValue)",
     "                    Text(state.label)", 1),
]


def main() -> int:
    failures = []
    touched = {}
    for rel, old, new, count in EDITS:
        path = ROOT / rel
        text = touched.get(rel)
        if text is None:
            text = path.read_text()
        found = text.count(old)
        if found != count:
            failures.append(f"{rel}: expected {count} occurrence(s) of {old[:70]!r}, found {found}")
            continue
        touched[rel] = text.replace(old, new)
    if failures:
        print("FAILED EDITS:")
        for f in failures:
            print("  -", f)
        return 1
    for rel, text in touched.items():
        (ROOT / rel).write_text(text)
    print(f"applied {len(EDITS)} edits across {len(touched)} files")
    return 0


if __name__ == "__main__":
    sys.exit(main())
