"""Isolated HTTP server, synthetic fixtures, SQL assertions and concurrency probe."""

import json
import sqlite3
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor
from contextlib import closing
from http.server import ThreadingHTTPServer
from pathlib import Path

import requests
from jsonschema import validate
from robot.api.deco import keyword
from demo.domain import initialize
from demo.server import Handler


class DemoLibrary:
    ROBOT_LIBRARY_SCOPE = "SUITE"

    @keyword
    def start_demo(self):
        temp_root = Path(__file__).parents[1] / "results"
        temp_root.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="transit-qa-", dir=temp_root)
        self.db = str(Path(self.temp.name) / "test.db")
        initialize(self.db)
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.server.db = self.db
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f"http://127.0.0.1:{self.server.server_port}"
        return self.url

    @keyword
    def stop_demo(self):
        if hasattr(self, "server"):
            self.server.shutdown()
            self.server.server_close()
            self.thread.join(timeout=5)
        if hasattr(self, "temp"):
            self.temp.cleanup()

    @keyword
    def reset_synthetic_data(self):
        # No public reset endpoint; fixture owns this disposable database.
        Path(self.db).unlink()
        initialize(self.db)

    @keyword
    def sql_value_should_be(self, query, expected):
        if not query.lstrip().upper().startswith("SELECT "):
            raise ValueError("Only SELECT assertions are supported")
        with closing(sqlite3.connect(self.db)) as conn:
            actual = conn.execute(query).fetchone()[0]
        assert str(actual) == str(expected), f"SQL expected {expected!r}, got {actual!r}: {query}"

    @keyword
    def reservation_should_match_contract(self, body):
        schema = json.loads((Path(__file__).parents[1] / "contracts/reservation.schema.json").read_text())
        validate(body, schema)

    @keyword
    def concurrent_seat_purchases_should_have_one_winner(self):
        def purchase(user):
            response = requests.post(self.url + "/api/reservations", timeout=10,
                headers={"Authorization": f"Bearer demo-rider-{user}"},
                json={"trip_id": "T-001", "seat": 2, "request_id": f"race-{user}"})
            return response.status_code
        with ThreadPoolExecutor(max_workers=2) as pool:
            statuses = list(pool.map(purchase, ["U-002", "U-005"]))
        assert sorted(statuses) == [201, 409], statuses
        self.sql_value_should_be("SELECT COUNT(*) FROM reservations WHERE trip_id='T-001' AND seat=2 AND status!='cancelled'", 1)
