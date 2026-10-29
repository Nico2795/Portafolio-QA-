"""Local-only transport sandbox. Fixed tokens are public synthetic fixtures."""

import argparse
import json
import sqlite3
from contextlib import closing
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from demo import domain


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, data):
        body = json.dumps(data, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path == "/":
            body = Path(__file__).with_name("index.html").read_bytes()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        self.handle_api()

    def do_POST(self):
        self.handle_api()

    def do_PATCH(self):
        self.handle_api()

    def handle_api(self):
        try:
            with closing(sqlite3.connect(self.server.db, timeout=10)) as conn, conn:
                conn.row_factory = sqlite3.Row
                if self.command != "GET":
                    conn.execute("BEGIN IMMEDIATE")
                status, body = self.dispatch(conn)
            # Reply only after commit, including event acknowledgement.
            self.reply(status, body)
        except domain.DomainError as error:
            self.reply(error.status, {"error": error.code})

    def dispatch(self, conn):
        if self.path == "/health" and self.command == "GET":
            return 200, {"status": "ok"}
        token = self.headers.get("Authorization", "").removeprefix("Bearer ")
        is_driver = token == "demo-driver-001"
        user = token.removeprefix("demo-rider-") if token.startswith("demo-rider-") else ""
        if not is_driver and not conn.execute("SELECT 1 FROM users WHERE id=?", (user,)).fetchone():
            domain.reject(401, "unauthorized")
        if self.path.startswith("/api/driver/") and not is_driver:
            domain.reject(403, "driver_required")
        parts = self.path.strip("/").split("/")
        if self.command == "GET" and len(parts) == 4 and parts[:3] == ["api", "driver", "manifest"]:
            return 200, domain.manifest(conn, parts[3])
        if self.command == "GET" and self.path == "/api/trips":
            return 200, [domain.manifest(conn, row[0]) for row in conn.execute("SELECT id FROM trips ORDER BY id")]
        if self.command not in ("POST", "PATCH"):
            domain.reject(404, "not_found")
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if not 0 < length <= 32768:
                raise ValueError
            data = json.loads(self.rfile.read(length))
        except (ValueError, UnicodeDecodeError):
            domain.reject(400, "invalid_json")
        if not isinstance(data, dict):
            domain.reject(422, "invalid_payload")
        # Bindings accept only scalar IDs; bad nested payloads never reach SQL.
        for key in ("trip_id", "user_id"):
            if key in data and not isinstance(data[key], str):
                domain.reject(422, "invalid_payload")
        if self.path == "/api/reservations" and self.command == "POST":
            if is_driver:
                domain.reject(403, "rider_required")
            return domain.purchase(conn, user, data)
        if len(parts) in (3, 4) and parts[:2] == ["api", "reservations"]:
            if self.command == "PATCH" and len(parts) == 3:
                return 200, domain.edit(conn, user, parts[2], data)
            if self.command == "POST" and len(parts) == 4 and parts[3] == "cancel":
                return 200, domain.cancel(conn, user, parts[2])
        if self.command == "POST":
            if self.path == "/api/driver/validate":
                return 200, domain.validate_passenger(conn, data)
            if self.path == "/api/driver/depart":
                return 200, domain.depart(conn, data)
            if self.path == "/api/driver/sync":
                return 200, domain.synchronize(conn, data)
        domain.reject(404, "not_found")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=8000)
    parser.add_argument("--db", default="demo.db")
    args = parser.parse_args()
    if not Path(args.db).exists():
        domain.initialize(args.db)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    server.db = args.db
    print(f"Transport QA: http://127.0.0.1:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
