"""Small local load probe, not a production capacity benchmark."""

import argparse
import json
import math
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import requests
from libraries.DemoLibrary import DemoLibrary


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--requests", type=int, default=100)
    parser.add_argument("--workers", type=int, default=4)
    parser.add_argument("--p95-ms", type=float, default=1000)
    args = parser.parse_args()
    if args.requests < 20 or args.workers < 1 or args.p95_ms <= 0:
        parser.error("Use requests >= 20, workers >= 1 and p95-ms > 0")
    fixture = DemoLibrary()
    try:
        url = fixture.start_demo()
        requests.get(url + "/health", timeout=5).raise_for_status()

        def sample(_):
            started = time.perf_counter()
            try:
                response = requests.get(url + "/api/driver/manifest/T-001", timeout=5,
                    headers={"Authorization": "Bearer demo-driver-001"})
                body = response.json()
                ok = (response.status_code == 200 and body["id"] == "T-001"
                      and body["available_seats"] == 2 and len(body["passengers"]) == 1)
            except (requests.RequestException, ValueError, KeyError, TypeError):
                ok = False
            return (time.perf_counter() - started) * 1000, ok

        started = time.perf_counter()
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            samples = list(pool.map(sample, range(args.requests)))
        elapsed = time.perf_counter() - started
        times = sorted(ms for ms, _ in samples)
        p95 = times[math.ceil(len(times) * 0.95) - 1]
        errors = sum(not ok for _, ok in samples)
        passed = errors == 0 and p95 <= args.p95_ms
        report = {"requests": args.requests, "workers": args.workers,
                  "errors": errors, "p95_ms": round(p95, 2),
                  "requests_per_second": round(args.requests / elapsed, 2),
                  "threshold_p95_ms": args.p95_ms, "passed": passed,
                  "scope": "local driver manifest read; illustrative threshold, not a production SLA"}
        output = ROOT / "results/performance"
        output.mkdir(parents=True, exist_ok=True)
        (output / "summary.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
        print(json.dumps(report, indent=2))
        return 0 if passed else 1
    finally:
        fixture.stop_demo()


if __name__ == "__main__":
    sys.exit(main())
