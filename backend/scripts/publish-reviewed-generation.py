"""Publish or maintain public-source drafts under the maintenance lock."""
import argparse
import fcntl
import os
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="absolute, initialized source maintenance root")
    maintenance = parser.add_mutually_exclusive_group()
    maintenance.add_argument("--maintain-drafts", action="store_true", help="run one bounded draft maintenance cycle")
    maintenance.add_argument("--maintain-sources", action="store_true", help="renew approved sources and maintain drafts")
    args = parser.parse_args()
    root = args.root
    state = root / "state"
    if not root.is_absolute() or any(
        path.is_symlink() or not path.is_dir() for path in (root, state, state / "generations")
    ):
        raise SystemExit("Expected an initialized absolute source root")
    entry = Path(__file__).resolve().parents[1] / "dist" / "publicDiscoveryPublishGeneration.js"
    if not entry.is_file():
        raise SystemExit("Build the backend before publishing")
    flags = os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK
    with os.fdopen(os.open(state / "refresh.lock", flags, 0o600), "r+") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            raise SystemExit("Another operation owns this source index") from None
        descriptor = lock.fileno()
        # Keep the flock and process identity when handing control to the publisher.
        os.set_inheritable(descriptor, True)
        mode = ["--maintain-sources"] if args.maintain_sources else ["--maintain-drafts"] if args.maintain_drafts else []
        os.execvp("node", ["node", str(entry), str(root), str(descriptor), *mode])


if __name__ == "__main__":
    raise SystemExit(main())
