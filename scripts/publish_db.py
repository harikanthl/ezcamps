#!/usr/bin/env python3
"""
Publish data/campsites.db as a GitHub release (`data-YYYY-MM-DD`) after a rebuild.

Compresses the database, writes its SHA-256, and creates the release with the GitHub
CLI (`gh`, signed in with write access to the repo). Run after `scripts/build_db.py`;
others then get it with `scripts/fetch_db.py`.

Usage:
  python3 -I scripts/publish_db.py            # tag data-<today>
  python3 -I scripts/publish_db.py --tag data-2026-12-01
"""

from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import shutil
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = "harikanthl/ezcamps"
ROOT = Path(__file__).resolve().parent.parent
DB = ROOT / "data" / "campsites.db"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default=f"data-{dt.date.today().isoformat()}")
    args = ap.parse_args()
    if not DB.exists():
        sys.exit(f"{DB} not found. Build it with scripts/build_db.py first.")

    conn = sqlite3.connect(f"file:{DB}?mode=ro", uri=True)
    sites = conn.execute("SELECT COUNT(*) FROM campsites").fetchone()[0]
    acts = conn.execute("SELECT COUNT(*) FROM activities").fetchone()[0]
    conn.close()

    with tempfile.TemporaryDirectory() as tmp:
        gz = Path(tmp) / "campsites.db.gz"
        with DB.open("rb") as src, gzip.open(gz, "wb", compresslevel=9) as dst:
            shutil.copyfileobj(src, dst)
        digest = hashlib.sha256(gz.read_bytes()).hexdigest()
        sha = Path(tmp) / "campsites.db.gz.sha256"
        sha.write_text(f"{digest}  campsites.db.gz\n")
        notes = (
            "SQLite database built by `scripts/build_db.py` (gzip-compressed).\n\n"
            f"- `campsites` table: {sites:,} deduplicated campsites\n"
            f"- `activities` table: {acts:,} activities ranked by difficulty\n\n"
            "Download and unpack with `python3 -I scripts/fetch_db.py` (verifies the SHA-256).\n\n"
            "Licenses vary by source; see each row's `license` column and `data/README.md`."
        )
        subprocess.run(["gh", "release", "create", args.tag, "-R", REPO, "--target", "main",
                        "--title", f"Data snapshot {args.tag.removeprefix('data-')}", "--notes", notes,
                        str(gz), str(sha)], check=True)
    print(f"published {args.tag}: {sites:,} campsites, {acts:,} activities", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
