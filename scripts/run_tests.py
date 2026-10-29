"""Same entry point locally and in CI; each suite owns its server and DB."""

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import robot  # noqa: E402


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--suite", choices=["api", "ui", "all"], default="all")
    parser.add_argument("--include", help="Robot tag, e.g. smoke")
    parser.add_argument("--output", default="results")
    args = parser.parse_args()
    target = ROOT / "tests" if args.suite == "all" else ROOT / "tests" / args.suite
    options = dict(outputdir=str(ROOT / args.output), xunit="junit.xml", loglevel="INFO")
    if args.include:
        options["include"] = args.include
    return robot.run(str(target), **options)


if __name__ == "__main__":
    sys.exit(main())
