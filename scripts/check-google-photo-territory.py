#!/usr/bin/env python3
"""Compile and execute the real territory policy without GPS, provider or simulator calls."""
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / "SAV-E/Services/GooglePlacesService.swift").read_text()
start = source.index("nonisolated enum GoogleMapsPlatformAvailability")
end = source.index("\nenum GoogleMapsAttributionMetrics", start)
fixture = 'let now = Date(timeIntervalSince1970: 10000)\nfunc check(_ condition: Bool, _ label: String) { if !condition { fatalError(label) } }\ncheck(!GoogleMapsPlatformAvailability.isAllowed(regionCode: nil, at: now), "unknown")\ncheck(!GoogleMapsPlatformAvailability.isAllowed(regionCode: "CN", at: now), "CN")\ncheck(!GoogleMapsPlatformAvailability.isAllowed(regionCode: "ZZ", at: now), "invalid")\ncheck(GoogleMapsPlatformAvailability.isAllowed(regionCode: "TW", observedAt: now, at: now), "TW")\ncheck(GoogleMapsPlatformAvailability.isAllowed(regionCode: "HK", observedAt: now, at: now), "HK")\ncheck(!GoogleMapsPlatformAvailability.isAllowed(regionCode: "US", observedAt: now.addingTimeInterval(-301), at: now), "stale")\ncheck(!GoogleMapsPlatformAvailability.isAllowed(regionCode: "US", observedAt: now.addingTimeInterval(61), at: now), "future")\nGoogleMapsPlatformAvailability.updateTerritory(regionCode: "TW", observedAt: now)\ncheck(GoogleMapsPlatformAvailability.isAllowed(at: now), "snapshot allow")\nGoogleMapsPlatformAvailability.updateTerritory(regionCode: nil)\ncheck(!GoogleMapsPlatformAvailability.isAllowed(at: now), "snapshot revoke")\nGoogleMapsPlatformAvailability.updateTerritory(regionCode: "CN", observedAt: now)\ncheck(!GoogleMapsPlatformAvailability.isAllowed(at: now), "snapshot CN")\nprint("PASS: actual territory policy unknown/CN/invalid/fresh TW/HK/stale/future/revocation")\n'
with tempfile.TemporaryDirectory(prefix="save-territory-") as directory:
    path = Path(directory) / "check.swift"
    path.write_text("import Foundation\n" + source[start:end] + "\n" + fixture)
    subprocess.run(["swift", "-module-cache-path", str(Path(directory) / "modules"), str(path)], check=True)
