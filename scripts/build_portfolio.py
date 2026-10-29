"""Build a static portfolio with real, passing Robot evidence for static hosting."""

import argparse
import json
import os
import shutil
from datetime import datetime, timezone
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--results", default="results/pages")
    parser.add_argument("--output", default="_site")
    args = parser.parse_args()
    results = (ROOT / args.results).resolve()
    output = (ROOT / args.output).resolve()
    if not output.is_relative_to(ROOT) or output == ROOT:
        parser.error("Output must be a subdirectory of the repository")
    suite = ElementTree.parse(results / "junit.xml").getroot()
    stats = {key: int(suite.get(key, "0")) for key in ("tests", "failures", "errors", "skipped")}
    if stats["tests"] < 1 or any(stats[key] for key in ("failures", "errors", "skipped")):
        raise SystemExit("Portfolio publication requires a nonempty, fully passing test run")
    for filename in ("report.html", "log.html"):
        if not (results / filename).is_file():
            raise SystemExit(f"Missing Robot evidence: {filename}")
    output.mkdir(parents=True, exist_ok=True)
    for path in (ROOT / "portfolio").iterdir():
        if path.is_file():
            shutil.copy2(path, output / path.name)
    (output / "assets").mkdir(exist_ok=True)
    shutil.copy2(ROOT / "docs/demo.png", output / "assets/demo.png")
    (output / "reports").mkdir(exist_ok=True)
    for filename in ("report.html", "log.html"):
        shutil.copy2(results / filename, output / "reports" / filename)
    evidence = {**stats, "generated_at": datetime.now(timezone.utc).isoformat(),
                "environment": "GitHub Actions / Linux" if os.getenv("GITHUB_ACTIONS") == "true" else "Ejecución local",
                "commit": os.getenv("GITHUB_SHA", "local")}
    (output / "evidence.json").write_text(json.dumps(evidence, indent=2), encoding="utf-8")
    (output / ".nojekyll").touch()
    print(f"Portfolio ready: {output}; {stats['tests']} passing tests")


if __name__ == "__main__":
    main()
