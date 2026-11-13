#!/usr/bin/env python3
"""Keep existing StoreKit test fixtures when XcodeGen regenerates main schemes."""
from pathlib import Path
import re
import xml.etree.ElementTree as ET

root = Path(__file__).resolve().parents[1]
for name in ("SAV-E", "Wanderly"):
    path = root / "SAV-E.xcodeproj/xcshareddata/xcschemes" / (name + ".xcscheme")
    text = path.read_text()
    tree = ET.fromstring(text)
    launch = tree.find("LaunchAction/StoreKitConfigurationFileReference")
    assert launch is not None, f"{name}: StoreKit run fixture missing from project.yml"
    test = tree.find("TestAction")
    assert test is not None, f"{name}: TestAction missing"
    existing = test.findall("StoreKitConfigurationFileReference")
    if existing:
        assert len(existing) == 1 and existing[0].attrib == launch.attrib
        continue
    block = re.search(r"      <StoreKitConfigurationFileReference\b.*?</StoreKitConfigurationFileReference>", text, re.S)
    assert block is not None
    assert text.count("   </TestAction>") == 1
    path.write_text(text.replace("   </TestAction>", block.group(0) + "\n   </TestAction>", 1))
