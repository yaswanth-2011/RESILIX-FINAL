#!/usr/bin/env python3
"""Wrap the remaining hard-coded user-visible literals in `L("…")`.

The script only touches literals that are listed in `TARGETS` and that are
not already inside an `L(` call, so it is safe to run repeatedly.

Usage:  python3 Tools/l10n/localize_literals.py [--dry]
"""
from __future__ import annotations

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent.parent

# ---------------------------------------------------------------------------
# User-visible strings that still live directly in the source code.
# The English text itself is the key of the string catalog, exactly like the
# strings that were migrated earlier.
# ---------------------------------------------------------------------------
FEATURE_STRINGS = [
    "1 hop", "2 hops", "AI BEHAVIOR", "AI FEATURES", "All AI runs on this device",
    "Allow microphone prompts", "Anonymous Analytics", "Apple Maps standard view",
    "Auto-relay when connected", "Check routes & latency", "Choose a username",
    "City Emergency", "Clear all conversations?", "Clear conversation?",
    "Clear this chat?", "Connected peers", "Conversation Storage", "Create Account",
    "Deep 3D with rotation", "Demo values", "Device A", "Device B",
    "Discover new mesh peers", "Downtown Group",
    "Drag to tilt the map from top-down (0°) to cinematic (75°).",
    "Dropped duplicates", "Email or username", "Emergency Steps",
    "Enter email and password.", "Field Medic Unit", "Fill in all fields.",
    "Find help close by", "Find nearby Resilix users to start communicating.",
    "First Aid", "Flat top-down map", "Give me emergency steps for a burn.",
    "Help improve offline AI quality", "Hold to send…", "Hop Count",
    "How do I treat a severe bleeding injury?", "Install file",
    "Keep conversation history", "Knowledge base", "Last event", "Local AI · Generic",
    "Local AI · Knowledge base", "Local Processing",
    "Map and SOS location sharing need location. Denied limits map features.",
    "Map highlighting public transport", "Mesh Connected", "Mesh Disconnected",
    "Mesh Events", "Mesh discovery requires Bluetooth. Enable in Settings if denied.",
    "Messages work without internet. Start a conversation.",
    "Microphone access is required to record a voice message.", "Mute Notifications",
    "Nearby Shelters", "New Messages", "No active SOS incidents.", "No conversations",
    "No incidents", "No link", "No offline map installed",
    "No peer is connected yet — scan for devices first.", "No results",
    "No route available. No peers nearby.",
    "No route yet — the message will be queued", "No runtime", "Not installed",
    "Offline keyword + knowledge base", "Offline knowledge base · No internet",
    "Offline map active", "Offline maps",
    "P2P Wi-Fi uses local network discovery. Denied limits peer discovery.",
    "Protocol version", "Pure satellite imagery", "Queued packets",
    "Realistic 3D buildings & terrain", "Recenter map", "Relay Mode",
    "Remember context across sessions", "Replace file", "Resilix Assist 1.0",
    "Resilix mesh test message", "Route test", "SOS Alerts", "Safety Tips",
    "Safety guide for staying in place during an emergency.",
    "Satellite imagery with roads & labels", "Saved locally, never uploaded",
    "Set mode to Tilted or Cinematic to adjust the 3D tilt.", "Shelter 1",
    "Shelter 2", "Show Debug Info", "Show answers word-by-word", "Sign In",
    "Soft, low-saturation map for overview", "Stay safe & calm",
    "Stored on this device only", "Stream Responses", "Subtle tilt for context",
    "Subtle vibration on responses", "Tap to record", "The file could not be opened.",
    "The map above uses the online Apple tiles. Import an .mbtiles pack to use the map without internet.",
    "The map pack could not be opened.", "The map pack was imported.",
    "The model file could not be opened.", "The model file was installed.",
    "The photo could not be stored.", "The profile photo was removed.",
    "The profile photo was saved.", "The test packet could not be sent.",
    "Treat injuries", "Unmute Notifications", "Voice Input",
    "Watch packet travel the mesh", "What to do now",
    "Where is the nearest shelter and hospital?",
]

CORE_STRINGS = [
    "First-aid knowledge base (on device)", "Bundled with the app",
    "Always available, no model needed", "Not supported on this device",
    "Mesh idle", "Map pack", "Apple Foundation Models",
    "The file is not a readable MBTiles container", "The file is empty",
    "The recorder could not be started", "Bluetooth is switched off",
    "Bluetooth permission denied", "Bluetooth LE is not supported on this device",
    "Bluetooth is resetting", "Connection failed", "Connection cancelled",
    "Bluetooth transport stopped", "Wi-Fi transport stopped",
    "Wi-Fi Aware not supported on this device",
    "Wi-Fi Aware connection requires the Apple-granted entitlement",
    "Dropped malformed frame",
]

TARGETS = {
    "Resilix/Features": FEATURE_STRINGS,
    "Resilix/Core": CORE_STRINGS,
}

dry = "--dry" in sys.argv
changed = 0
for folder, strings in TARGETS.items():
    for path in sorted((ROOT / folder).rglob("*.swift")):
        src = path.read_text()
        original = src
        for text in strings:
            needle = '"' + text + '"'
            index = 0
            while True:
                pos = src.find(needle, index)
                if pos < 0:
                    break
                prefix = src[max(0, pos - 4):pos]
                if prefix.rstrip().endswith("L("):
                    index = pos + len(needle)
                    continue
                src = src[:pos] + 'L(' + needle + ')' + src[pos + len(needle):]
                index = pos + len(needle) + 3
        if src != original:
            changed += 1
            print(("would patch " if dry else "patched ") + str(path.relative_to(ROOT)))
            if not dry:
                path.write_text(src)
print("files changed:", changed)
