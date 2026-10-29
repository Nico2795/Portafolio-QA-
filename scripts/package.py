"""Build a reviewable source bundle only after CI gates pass."""

from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

ROOT = Path(__file__).resolve().parents[1]
destination = ROOT / "dist/qa-portfolio.zip"
destination.parent.mkdir(exist_ok=True)
with ZipFile(destination, "w", ZIP_DEFLATED) as bundle:
    for directory in ("demo", "libraries", "resources", "tests", "scripts", "contracts", "docs", ".github"):
        for path in sorted((ROOT / directory).rglob("*")):
            if path.is_file() and "__pycache__" not in path.parts:
                bundle.write(path, path.relative_to(ROOT))
    for name in ("README.md", "requirements.txt", ".gitignore"):
        bundle.write(ROOT / name, name)
print(destination)
