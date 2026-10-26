"""Pending Clip intent must not become saved state without a full-App tap."""
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[2]
class ClipPendingConfirmationTests(unittest.TestCase):
    def test_clip_has_no_direct_identity_or_place_write(self):
        source = (ROOT / "SAV-EClip/ClipSaveService.swift").read_text()
        self.assertFalse('request.httpMethod = "POST"' in source)
        self.assertFalse('ClipAppleAuth' in source)
        self.assertFalse('case saved' in source)
        self.assertIn('case pending(Int)', source)
    def test_app_requires_explicit_confirmation(self):
        source = (ROOT / "SAV-E/App/ContentView.swift").read_text()
        self.assertFalse('performPendingShareAutoSave' in source)
        self.assertFalse('runLatest(' in source)
        self.assertIn('app.handoff.confirmList', source)
        self.assertIn('clear(ifUnchanged:', source)
    def test_auth_restore_does_not_request_clip_identity(self):
        source = (ROOT / "SAV-E/Services/PrivyAuthService.swift").read_text()
        restore = source.split('func restoreSession()', 1)[1].split('private func observeAuthState()', 1)[0]
        self.assertFalse('restoreClipSignInIfNeeded' in restore)
        self.assertFalse('ClipAppleSessionExchange.exchange' in restore)
    def test_verifier_tracks_pending_confirmation_contract(self):
        source = (ROOT / "scripts/save_verify.py").read_text()
        self.assertIn('307: ("clip.pending", "app.handoff.confirmList", "clip.skoverlay")', source)
        self.assertIn('for token in ("clip.pending", "app.handoff.confirmList", "clip.skoverlay")', source)
