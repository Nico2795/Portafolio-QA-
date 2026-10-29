"""Controlled in-memory defect: wrongly accept a walk-in on a full trip."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

import robot
from robot.api import ExecutionResult
from demo import domain


def main():
    original = domain.validate_passenger

    def defective_validation(conn, data):
        if data.get("trip_id") == "T-FULL" and data.get("user_id") == "U-002":
            return {"code": "walk_in_validated", "reservation_id": "MUTANT", "seat": 3}
        return original(conn, data)

    output = ROOT / "results/mutation"
    try:
        domain.validate_passenger = defective_validation
        code = robot.run(str(ROOT / "tests/api/driver.robot"), test="DRV-002*", outputdir=str(output))
    finally:
        domain.validate_passenger = original
    result = ExecutionResult(str(output / "output.xml"))
    cases = list(result.suite.tests)
    detected = (code == 1 and len(cases) == 1 and cases[0].failed
                and "200 != 409" in cases[0].message)
    print("Full-trip validation defect detected" if detected else "Unexpected mutation result")
    return 0 if detected else 1


if __name__ == "__main__":
    sys.exit(main())
