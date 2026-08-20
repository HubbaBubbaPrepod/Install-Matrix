#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$PROJECT_DIR"

python3 - <<'PY'
import pathlib
import re
import struct
import xml.etree.ElementTree as ET

root = pathlib.Path.cwd()
installer = (root / "install-matrix.sh").read_text(encoding="utf-8")
match = re.search(r'^INSTALLER_VERSION="([^"]+)"$', installer, re.MULTILINE)
if not match:
    raise SystemExit("INSTALLER_VERSION not found")
version = match.group(1)

for required in (root / "README.MD", root / "CHANGELOG.md"):
    if version not in required.read_text(encoding="utf-8"):
        raise SystemExit(f"Version {version} is missing from {required.name}")

language_pairs = (
    ("README.en.md", "README.MD"),
    ("BACKUP.md", "BACKUP.ru.md"),
    ("UPDATE.md", "UPDATE.ru.md"),
    ("UNINSTALL.md", "UNINSTALL.ru.md"),
    ("SECURITY.md", "SECURITY.ru.md"),
    ("CONTRIBUTING.md", "CONTRIBUTING.ru.md"),
    ("CODE_OF_CONDUCT.md", "CODE_OF_CONDUCT.ru.md"),
    ("SUPPORT.md", "SUPPORT.ru.md"),
    ("CHANGELOG.md", "CHANGELOG.ru.md"),
    ("docs/ARCHITECTURE.md", "docs/ARCHITECTURE.ru.md"),
    ("docs/FAQ.md", "docs/FAQ.ru.md"),
)
for english_name, russian_name in language_pairs:
    english = root / english_name
    russian = root / russian_name
    if russian.name not in english.read_text(encoding="utf-8"):
        raise SystemExit(f"Missing Russian link in {english_name}")
    if english.name not in russian.read_text(encoding="utf-8"):
        raise SystemExit(f"Missing English link in {russian_name}")

link_pattern = re.compile(r'!?\[[^\]]*\]\(([^)]+)\)')
for document in root.rglob("*"):
    if document.suffix.lower() != ".md" or ".git" in document.parts:
        continue
    text = document.read_text(encoding="utf-8")
    for raw_target in link_pattern.findall(text):
        target = raw_target.strip().strip("<>").split("#", 1)[0]
        if not target or re.match(r"^[a-z][a-z0-9+.-]*:", target, re.I):
            continue
        resolved = (document.parent / target).resolve()
        if not resolved.exists():
            raise SystemExit(f"Broken local link in {document.relative_to(root)}: {raw_target}")

for svg in (root / "docs" / "assets").glob("*.svg"):
    ET.parse(svg)

preview = root / "docs" / "assets" / "social-preview.png"
data = preview.read_bytes()
if data[:8] != b"\x89PNG\r\n\x1a\n":
    raise SystemExit("social-preview.png is not a PNG")
width, height = struct.unpack(">II", data[16:24])
if width < 1200 or height < 600 or not 1.9 <= width / height <= 2.1:
    raise SystemExit(f"Unexpected social preview dimensions: {width}x{height}")
if len(data) >= 1_000_000:
    raise SystemExit(f"Social preview exceeds GitHub's 1 MB limit: {len(data)} bytes")

print(f"Documentation checks passed (version {version}, preview {width}x{height}, {len(data)} bytes)")
PY
