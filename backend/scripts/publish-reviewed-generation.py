"""Publish an approved public-source generation under the maintenance lock."""
import argparse
import fcntl
import os
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", type=Path, help="absolute, initialized source maintenance root")
    root = parser.parse_args().root
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
        os.execvp("node", ["node", str(entry), str(root), str(descriptor)])


if __name__ == "__main__":
    raise SystemExit(main())
