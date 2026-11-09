#!/usr/bin/env python3
"""Fail before packaging a plist for an unverified API origin. Never print secrets."""
import argparse
import plistlib
import sys
from urllib.parse import urlsplit

KNOWN_HOSTS = {"wanderly-api-production.up.railway.app", "save-backend-production.up.railway.app"}


def origin(value):
    if not isinstance(value, str):
        raise ValueError("API origin must be a string")
    value = value.strip().rstrip("/")
    parsed = urlsplit(value)
    if (parsed.scheme != "https" or parsed.hostname not in KNOWN_HOSTS
            or parsed.netloc != parsed.hostname or parsed.path or parsed.query or parsed.fragment):
        raise ValueError("API origin must be one of the two known HTTPS backend origins")
    return value


def verify(plist, expected):
    expected = origin(expected)
    primary = plist.get("SAVE_API_URL")
    legacy = plist.get("WANDERLY_API_URL")
    # Do not allow fallback/placeholder ambiguity in a distributed build.
    effective = origin(primary)
    if effective != expected:
        raise ValueError("Release API does not match SAVE_EXPECTED_API_URL; preserve account data before changing it")
    if legacy is not None and origin(legacy) != expected:
        raise ValueError("Legacy API alias conflicts with the expected release origin")
    return effective


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--plist", required=True)
    parser.add_argument("--expected", required=True)
    args = parser.parse_args()
    try:
        with open(args.plist, "rb") as handle:
            verify(plistlib.load(handle), args.expected)
    except (ValueError, OSError, plistlib.InvalidFileException, TypeError):
        print("error: Release API origin validation failed. Check SAVE_EXPECTED_API_URL and both API URL keys; do not switch accounts without a verified data-preservation plan.", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
