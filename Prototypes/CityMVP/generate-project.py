#!/usr/bin/env python3
"""Generate a separate local target; never rewrite SAV-E.xcodeproj/project.yml."""
from pathlib import Path
import copy
import argparse
import json
import subprocess
from urllib.parse import urlsplit
import yaml

root = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--guide-config', type=Path, help='Explicit local Guide endpoint configuration; no credentials')
args = parser.parse_args()
guide = None
if args.guide_config:
    try:
        raw = args.guide_config.read_bytes()
        if len(raw) > 4096:
            raise ValueError()
        guide = json.loads(raw)
        if not isinstance(guide, dict) or set(guide) != {'allowRequests', 'apiBaseURL'} or type(guide['allowRequests']) is not bool or not isinstance(guide['apiBaseURL'], str):
            raise ValueError()
        endpoint = guide['apiBaseURL']
        if endpoint:
            url = urlsplit(endpoint)
            if url.port is not None and not 1 <= url.port <= 65535:
                raise ValueError()
            if any(c.isspace() or ord(c) < 32 or ord(c) == 127 for c in endpoint) or not url.hostname or url.username is not None or url.password is not None or url.query or url.fragment or url.path not in ('', '/'):
                raise ValueError()
            if url.scheme != 'https' and not (url.scheme == 'http' and url.hostname in ('127.0.0.1', 'localhost', '::1')):
                raise ValueError()
        elif guide['allowRequests']:
            raise ValueError()
    except (OSError, ValueError, TypeError, KeyError):
        parser.error('Guide config must contain only allowRequests (boolean) and apiBaseURL (HTTPS root or localhost HTTP), with no credentials.')
base = yaml.safe_load((root / 'project.yml').read_text())
# The archived separate harness must never post-process main app schemes.
base.get('options', {}).pop('postGenCommand', None)
app = copy.deepcopy(base['targets']['SAVE'])
app['sources'] += [
    {'path': 'Prototypes/CityMVP/Sources'},
    {'path': 'Prototypes/CityMVP/Resources', 'buildPhase': 'resources'},
]
app.pop('postBuildScripts', None)
app['sources'][0]['excludes'].append('Info.plist')
app['dependencies'] = [d for d in app['dependencies'] if 'package' in d]
# No production debug injection frameworks in the local test binary.
app['settings']['configs']['Debug']['OTHER_LDFLAGS'] = '$(inherited)'
app['settings']['configs']['Debug']['SWIFT_ACTIVE_COMPILATION_CONDITIONS'] = 'SAVVY_CITY_MVP'
settings = app['settings']['base']
settings.update({
    'PRODUCT_BUNDLE_IDENTIFIER': 'local.savvy.city-mvp',
    'PRODUCT_MODULE_NAME': 'SavvyCityMVP',
    'SWIFT_ACTIVE_COMPILATION_CONDITIONS': 'SAVVY_CITY_MVP',
    'CODE_SIGNING_ALLOWED': 'NO',
    'CODE_SIGN_ENTITLEMENTS': '',
    'DEVELOPMENT_TEAM': '',
    'SUPPORTS_MACCATALYST': 'NO',
    'COMPILER_INDEX_STORE_ENABLE': 'NO',
    'SWIFT_ENABLE_COMPILATION_CACHE': 'NO',
    'ARCHS': 'arm64',
})
app['info'] = {
    'path': 'Prototypes/CityMVP/Info.generated.plist',
    'properties': {
        'CFBundleDisplayName': 'Savvy City Lab',
        'CFBundleShortVersionString': '0.1.0',
        'CFBundleVersion': '1',
        'UILaunchScreen': {},
        'UIApplicationSceneManifest': {'UIApplicationSupportsMultipleScenes': False},
        'UISupportedInterfaceOrientations': ['UIInterfaceOrientationPortrait'],
        'NSLocationWhenInUseUsageDescription': 'Only if requested, show your location on the Apple Maps comparison.',
    }
}
if guide is not None:
    app['info']['properties']['CITY_MVP_GUIDE_ALLOW_REQUESTS'] = guide['allowRequests']
    app['info']['properties']['CITY_MVP_GUIDE_API_URL'] = guide['apiBaseURL'].rstrip('/')
base['name'] = 'SavvyCityMVP'
base['targets'] = {}
base['targets']['SavvyCityMVP'] = app
base['targets']['CityMVPTests'] = {
    'type': 'bundle.unit-test', 'platform': 'iOS',
    'sources': [{'path': 'Prototypes/CityMVP/Tests'}],
    'dependencies': [{'target': 'SavvyCityMVP'}],
    'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'local.savvy.city-mvp.tests', 'GENERATE_INFOPLIST_FILE': True,
                          'CODE_SIGNING_ALLOWED': 'NO', 'DEVELOPMENT_TEAM': '',
                          'SWIFT_DEFAULT_ACTOR_ISOLATION': 'nonisolated'}},
}
base['targets']['CityMVPVisualTests'] = {
    'type': 'bundle.ui-testing', 'platform': 'iOS',
    'sources': [{'path': 'Prototypes/CityMVP/VisualTests'}],
    'dependencies': [{'target': 'SavvyCityMVP'}],
    'settings': {'base': {'PRODUCT_BUNDLE_IDENTIFIER': 'local.savvy.city-mvp.visual-tests',
                          'GENERATE_INFOPLIST_FILE': True, 'CODE_SIGNING_ALLOWED': 'NO',
                          'DEVELOPMENT_TEAM': '', 'SWIFT_DEFAULT_ACTOR_ISOLATION': 'nonisolated'}},
}
base['schemes'] = {
    'SavvyCityMVP': {
        'build': {'targets': {'SavvyCityMVP': 'all', 'CityMVPTests': ['test'], 'CityMVPVisualTests': ['test']}},
        'run': {'config': 'Debug'},
        'test': {'config': 'Debug', 'targets': ['CityMVPTests', 'CityMVPVisualTests']},
    }
}
base['settings']['base']['DEVELOPMENT_TEAM'] = ''
spec = root / 'project-city-mvp.generated.yml'
spec.write_text(yaml.safe_dump(base, sort_keys=False))
subprocess.run(['xcodegen', 'generate', '--spec', str(spec), '--project', str(root)], check=True, cwd=root)
