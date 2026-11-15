#!/usr/bin/env python3
"""
Download the latest data/campsites.db from the repo's GitHub releases.

The database is too big to keep in git (it was ~60 MB and every rebuild added a full
copy to history), so each snapshot is published as a release named `data-YYYY-MM-DD`
with `campsites.db.gz` and its SHA-256. This script finds the newest one, verifies
the checksum, and unpacks it.

Usage:
  python3 -I scripts/fetch_db.py              # newest data release
  python3 -I scripts/fetch_db.py --tag data-2026-11-15
  python3 -I scripts/fetch_db.py --force      # overwrite an existing data/campsites.db

Stdlib only; no GitHub sign-in needed (the repo is public).
"""

from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import shutil
import sys
import tempfile
import urllib.request
from pathlib import Path

REPO = "harikanthl/ezcamps"
ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "data" / "campsites.db"
ASSET = "campsites.db.gz"


def get(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": "ezcamps-fetch-db", "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def find_release(tag: str | None) -> dict:
    if tag:
        return json.loads(get(f"https://api.github.com/repos/{REPO}/releases/tags/{tag}"))
    releases = json.loads(get(f"https://api.github.com/repos/{REPO}/releases?per_page=50"))
    data = [r for r in releases if r["tag_name"].startswith("data-") and not r.get("draft")]
    if not data:
        sys.exit("No data-* release found.")
    return max(data, key=lambda r: r["tag_name"])  # data-YYYY-MM-DD sorts by date


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", help="release tag, e.g. data-2026-11-15 (default: newest)")
    ap.add_argument("--force", action="store_true", help="overwrite an existing database")
    args = ap.parse_args()

    if DB.exists() and not args.force:
        sys.exit(f"{DB} already exists. Use --force to replace it.")

    release = find_release(args.tag)
    assets = {a["name"]: a["browser_download_url"] for a in release["assets"]}
    if ASSET not in assets:
        sys.exit(f"{release['tag_name']} has no {ASSET}.")
    print(f"downloading {release['tag_name']} …", file=sys.stderr)

    with tempfile.TemporaryDirectory() as tmp:
        gz = Path(tmp) / ASSET
        req = urllib.request.Request(assets[ASSET], headers={"User-Agent": "ezcamps-fetch-db"})
        with urllib.request.urlopen(req, timeout=600) as r, gz.open("wb") as out:
            shutil.copyfileobj(r, out)

        if f"{ASSET}.sha256" in assets:
            expected = get(assets[f"{ASSET}.sha256"]).decode().split()[0]
            actual = hashlib.sha256(gz.read_bytes()).hexdigest()
            if actual != expected:
                sys.exit(f"Checksum mismatch: expected {expected}, got {actual}. Not installing.")
            print("checksum ok", file=sys.stderr)

        DB.parent.mkdir(parents=True, exist_ok=True)
        part = DB.with_suffix(".db.part")
        with gzip.open(gz, "rb") as src, part.open("wb") as dst:
            shutil.copyfileobj(src, dst)
        part.replace(DB)

    print(f"wrote {DB} ({DB.stat().st_size / 1048576:.1f} MB) from {release['tag_name']}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
