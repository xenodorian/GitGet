#!/usr/bin/env python3
"""Build the GitGet diagnostic ZIP (standard library only, deterministic).

Usage: python3 tools/build_diagnostic.py [--out DIR]

Reads src/diagnostic/, writes GitGet-Diagnostic-<version>.zip and a .sha256
file into DIR (default: dist/). The ZIP is meant to be extracted at the root
of the microSD partition that holds the ROM folders, so every path in it
starts with "ports/".
"""
import argparse
import hashlib
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "src" / "diagnostic"
SCRIPT_REL = "ports/GitGet Diagnostic.sh"
MANIFEST_REL = "ports/gitget-diag/MANIFEST.txt"
FIXED_TIME = (2026, 10, 11, 0, 0, 0)
TEXT_SUFFIXES = {".sh", ".txt", ".md"}
SKIP_PARTS = {".git", "__pycache__", ".DS_Store"}


def collect_files():
    files = {}
    for path in sorted(SRC.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(SRC).as_posix()
        if any(part in SKIP_PARTS for part in rel.split("/")) or rel.endswith((".pyc", ".pyo")):
            continue
        if rel.startswith("/") or ".." in rel.split("/"):
            raise SystemExit(f"Unsafe path: {rel}")
        if rel == MANIFEST_REL:
            raise SystemExit("MANIFEST.txt is generated; remove it from src/diagnostic")
        data = path.read_bytes()
        if path.suffix in TEXT_SUFFIXES and b"\r" in data:
            raise SystemExit(f"Windows line endings found in {rel}; use Unix line endings")
        files[rel] = data
    if SCRIPT_REL not in files:
        raise SystemExit(f"Missing {SCRIPT_REL}")
    return files


def script_version(files):
    match = re.search(rb'^GG_VERSION="([0-9][0-9A-Za-z.\-]*)"', files[SCRIPT_REL], re.M)
    if not match:
        raise SystemExit("GG_VERSION not found in the launcher script")
    return match.group(1).decode()


def manifest_text(files, version):
    lines = [f"GitGet Diagnostic {version} package manifest", "sha256  size  path"]
    for rel in sorted(files):
        data = files[rel]
        lines.append(f"{hashlib.sha256(data).hexdigest()}  {len(data)}  {rel}")
    return "\n".join(lines) + "\n"


def build(out_dir):
    files = collect_files()
    version = script_version(files)
    files[MANIFEST_REL] = manifest_text(files, version).encode()
    out_dir.mkdir(parents=True, exist_ok=True)
    zip_path = out_dir / f"GitGet-Diagnostic-{version}.zip"
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for rel in sorted(files):
            info = zipfile.ZipInfo(rel, date_time=FIXED_TIME)
            info.create_system = 3
            info.compress_type = zipfile.ZIP_DEFLATED
            mode = 0o755 if rel.endswith(".sh") else 0o644
            info.external_attr = (0o100000 | mode) << 16
            archive.writestr(info, files[rel])
    digest = hashlib.sha256(zip_path.read_bytes()).hexdigest()
    (out_dir / (zip_path.name + ".sha256")).write_text(f"{digest}  {zip_path.name}\n")
    # Re-open to confirm the archive is readable and intact.
    with zipfile.ZipFile(zip_path) as archive:
        bad = archive.testzip()
        if bad is not None:
            raise SystemExit(f"Corrupt member after build: {bad}")
    return zip_path, digest


def main():
    parser = argparse.ArgumentParser(description="Build the GitGet diagnostic ZIP")
    parser.add_argument("--out", type=Path, default=ROOT / "dist")
    args = parser.parse_args()
    zip_path, digest = build(args.out)
    print(f"{zip_path}\nsha256 {digest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
