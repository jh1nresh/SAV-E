#!/usr/bin/env python3
"""Prepare a tiny native verifier sharing the actual gallery and brand tokens."""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--output', type=Path, required=True)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[2]
out = args.output.resolve()
out.mkdir(parents=True, exist_ok=True)
tokens = (repo / 'SAV-E/Extensions/Color+Theme.swift').read_text()
brand = re.search(r'enum SaveBrandUI \{.*?\n\}', tokens, re.S).group()
# Extract canonical tokens every time; no separately maintained preview palette.
helper = '''import SwiftUI
import UIKit
extension Color {
    init(hex: String) { self.init(uiColor: UIColor(rgb: hex)) }
    init(light: String, dark: String) {
        self.init(uiColor: UIColor.adaptive(light: light, dark: dark))
    }
}
private extension UIColor {
    nonisolated static func adaptive(light: String, dark: String) -> UIColor {
        UIColor { traits in UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light) }
    }
    nonisolated convenience init(rgb: String) {
        let number = UInt32(rgb, radix: 16) ?? 0
        self.init(red: CGFloat((number >> 16) & 255) / 255, green: CGFloat((number >> 8) & 255) / 255,
                  blue: CGFloat(number & 255) / 255, alpha: 1)
    }
}
'''
(out / 'Brand.swift').write_text(helper + brand + '\n')
sources = [
    {'path': str(repo / 'Prototypes/SavedGalleryPreview/Sources')},
    {'path': str(repo / 'Prototypes/DatePlanDemo/Main/SavedGalleryWall.swift')},
    {'path': str(out / 'Brand.swift')},
    {'path': str(repo / 'Prototypes/TaipeiPocketCity/place-photo-data.js'), 'buildPhase': 'resources'},
    {'path': str(repo / 'Prototypes/TaipeiPocketCity/assets/place-photos'), 'buildPhase': 'resources'},
]
spec = {
    'name': 'SavvySavedGallery',
    'options': {'deploymentTarget': {'iOS': '17.0'}},
    'settings': {'base': {'SWIFT_VERSION': '6.0', 'SWIFT_DEFAULT_ACTOR_ISOLATION': 'MainActor', 'CODE_SIGNING_ALLOWED': 'NO',
                          'COMPILER_INDEX_STORE_ENABLE': 'NO', 'TARGETED_DEVICE_FAMILY': '1'}},
    'targets': {
        'SavvySavedGallery': {
            'type': 'application', 'platform': 'iOS', 'sources': sources,
            'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'local.savvy.saved-gallery',
                'GENERATE_INFOPLIST_FILE': 'YES', 'INFOPLIST_KEY_UILaunchScreen_Generation': 'YES',
                'INFOPLIST_KEY_UIApplicationSceneManifest_Generation': 'YES'}},
        },
        'GalleryUITests': {
            'type': 'bundle.ui-testing', 'platform': 'iOS',
            'sources': [{'path': str(repo / 'Prototypes/SavedGalleryPreview/UITests')}],
            'dependencies': [{'target': 'SavvySavedGallery'}],
            'settings': {'base': {'GENERATE_INFOPLIST_FILE': 'YES',
                'PRODUCT_BUNDLE_IDENTIFIER': 'local.savvy.saved-gallery.tests',
                'SWIFT_DEFAULT_ACTOR_ISOLATION': 'nonisolated'}},
        },
    },
    'schemes': {'SavvySavedGallery': {
        'build': {'targets': {'SavvySavedGallery': 'all'}},
        'test': {'targets': ['GalleryUITests']},
    }},
}
(out / 'project.json').write_text(json.dumps(spec, indent=2) + '\n')
print(out / 'project.json')
