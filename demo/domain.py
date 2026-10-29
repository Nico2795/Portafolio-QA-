"""Fictional transport rules. All money is simulated integer CLP."""

import json
import sqlite3
import uuid
from pathlib import Path

ALLOW_WALK_IN = True


class DomainError(Exception):
    def __init__(self, status, code):
        self.status, self.code = status, code


def reject(status, code):
    raise DomainError(status, code)


def initialize(db):
    conn = sqlite3.connect(db)
    try:
        conn.executescript("""
            CREATE TABLE users (id TEXT PRIMARY KEY);
            CREATE TABLE trips (id TEXT PRIMARY KEY, route TEXT, capacity INTEGER,
                fare INTEGER, status TEXT NOT NULL DEFAULT 'scheduled');
            CREATE TABLE reservations (id TEXT PRIMARY KEY, trip_id TEXT, user_id TEXT,
                seat INTEGER, status TEXT, amount INTEGER, request_id TEXT UNIQUE);
            CREATE UNIQUE INDEX occupied_seat ON reservations(trip_id, seat)
                WHERE status != 'cancelled';
            CREATE UNIQUE INDEX active_passenger ON reservations(trip_id, user_id)
                WHERE status != 'cancelled';
            CREATE TABLE refunds (id TEXT PRIMARY KEY, reservation_id TEXT UNIQUE, amount INTEGER);
            CREATE TABLE events (id TEXT PRIMARY KEY, payload TEXT, result TEXT);
        """)
        data = json.loads(Path(__file__).with_name("data.json").read_text(encoding="utf-8"))
        conn.executemany("INSERT INTO users VALUES (?)", [(u,) for u in data["users"]])
        for trip in data["trips"]:
            conn.execute("INSERT INTO trips(id, route, capacity, fare) VALUES (?, ?, ?, ?)",
                         (trip["id"], trip["route"], trip["capacity"], trip["fare"]))
        for row in data["reservations"]:
            conn.execute("INSERT INTO reservations VALUES (?, ?, ?, ?, 'confirmed', 5000, NULL)",
                         (row["id"], row["trip_id"], row["user_id"], row["seat"]))
        conn.commit()
    finally:
        conn.close()


def trip(conn, trip_id):
    row = conn.execute("SELECT * FROM trips WHERE id=?", (trip_id,)).fetchone()
    if row is None:
        reject(404, "trip_not_found")
    return dict(row)


def available_seat(conn, target, requested=None):
    occupied = {r[0] for r in conn.execute(
        "SELECT seat FROM reservations WHERE trip_id=? AND status!='cancelled'", (target["id"],))}
    if requested is not None:
        if type(requested) is not int or not 1 <= requested <= target["capacity"]:
            reject(422, "invalid_seat")
        if requested in occupied:
            reject(409, "seat_taken")
        return requested
    free = sorted(set(range(1, target["capacity"] + 1)) - occupied)
    if not free:
        reject(409, "no_seats")
    return free[0]


def manifest(conn, trip_id):
    target = trip(conn, trip_id)
    target["passengers"] = [dict(row) for row in conn.execute(
        "SELECT id, user_id, seat, status FROM reservations WHERE trip_id=? AND status!='cancelled' ORDER BY seat",
        (trip_id,))]
    target["available_seats"] = target["capacity"] - len(target["passengers"])
    return target


def purchase(conn, user, data):
    trip_id, seat, request_id = data.get("trip_id"), data.get("seat"), data.get("request_id")
    if not isinstance(request_id, str) or not 1 <= len(request_id) <= 100:
        reject(422, "invalid_request_id")
    previous = conn.execute("SELECT * FROM reservations WHERE request_id=?", (request_id,)).fetchone()
    if previous:
        if previous["user_id"] != user or previous["trip_id"] != trip_id or previous["seat"] != seat:
            reject(409, "idempotency_conflict")
        return 200, dict(previous)
    target = trip(conn, trip_id)
    if target["status"] != "scheduled":
        reject(409, "trip_departed")
    if conn.execute("SELECT 1 FROM reservations WHERE trip_id=? AND user_id=? AND status!='cancelled'",
                    (trip_id, user)).fetchone():
        reject(409, "already_reserved")
    # Explicit seat required for simulated ticket purchase.
    if seat is None:
        reject(422, "invalid_seat")
    available_seat(conn, target, seat)
    reservation_id = "R-" + uuid.uuid4().hex[:12]
    conn.execute("INSERT INTO reservations VALUES (?, ?, ?, ?, 'confirmed', ?, ?)",
                 (reservation_id, trip_id, user, seat, target["fare"], request_id))
    return 201, dict(conn.execute("SELECT * FROM reservations WHERE id=?", (reservation_id,)).fetchone())


def own_reservation(conn, user, reservation_id):
    row = conn.execute("SELECT * FROM reservations WHERE id=?", (reservation_id,)).fetchone()
    if row is None:
        reject(404, "reservation_not_found")
    if row["user_id"] != user:
        reject(403, "not_owner")
    return dict(row)


def edit(conn, user, reservation_id, data):
    row = own_reservation(conn, user, reservation_id)
    target = trip(conn, row["trip_id"])
    if row["status"] != "confirmed" or target["status"] != "scheduled":
        reject(409, "reservation_not_editable")
    seat = data.get("seat")
    if type(seat) is not int or not 1 <= seat <= target["capacity"]:
        reject(422, "invalid_seat")
    if seat != row["seat"]:
        available_seat(conn, target, seat)
        conn.execute("UPDATE reservations SET seat=? WHERE id=?", (seat, reservation_id))
    return dict(conn.execute("SELECT * FROM reservations WHERE id=?", (reservation_id,)).fetchone())


def cancel(conn, user, reservation_id):
    row = own_reservation(conn, user, reservation_id)
    existing = conn.execute("SELECT * FROM refunds WHERE reservation_id=?", (reservation_id,)).fetchone()
    if existing:
        return dict(existing)
    if row["status"] != "confirmed" or trip(conn, row["trip_id"])["status"] != "scheduled":
        reject(409, "reservation_not_cancellable")
    conn.execute("UPDATE reservations SET status='cancelled' WHERE id=?", (reservation_id,))
    refund = {"id": "F-" + uuid.uuid4().hex[:12], "reservation_id": reservation_id, "amount": row["amount"]}
    conn.execute("INSERT INTO refunds VALUES (?, ?, ?)", tuple(refund.values()))
    return refund


def validate_passenger(conn, data):
    trip_id, user = data.get("trip_id"), data.get("user_id")
    target = trip(conn, trip_id)
    if target["status"] != "scheduled":
        reject(409, "trip_departed")
    if not isinstance(user, str) or not conn.execute("SELECT 1 FROM users WHERE id=?", (user,)).fetchone():
        reject(404, "user_not_found")
    row = conn.execute("SELECT * FROM reservations WHERE trip_id=? AND user_id=? AND status!='cancelled'",
                       (trip_id, user)).fetchone()
    if row:
        if row["status"] == "boarded":
            reject(409, "already_validated")
        conn.execute("UPDATE reservations SET status='boarded' WHERE id=?", (row["id"],))
        return {"code": "validated", "reservation_id": row["id"], "seat": row["seat"]}
    if not ALLOW_WALK_IN:
        reject(409, "reservation_required")
    seat = available_seat(conn, target)
    reservation_id = "W-" + uuid.uuid4().hex[:12]
    # Walk-in is a shuttle seat assignment, not a charged ticket.
    conn.execute("INSERT INTO reservations VALUES (?, ?, ?, ?, 'boarded', 0, NULL)",
                 (reservation_id, trip_id, user, seat))
    return {"code": "walk_in_validated", "reservation_id": reservation_id, "seat": seat}


def depart(conn, data):
    target = trip(conn, data.get("trip_id"))
    if target["status"] != "scheduled":
        reject(409, "trip_departed")
    if not conn.execute("SELECT 1 FROM reservations WHERE trip_id=? AND status='boarded'",
                        (target["id"],)).fetchone():
        reject(409, "no_boarded_passengers")
    conn.execute("UPDATE trips SET status='departed' WHERE id=?", (target["id"],))
    return {"code": "departure_started", "trip_id": target["id"]}


def synchronize(conn, data):
    events = data.get("events")
    if not isinstance(events, list) or not 1 <= len(events) <= 50:
        reject(422, "invalid_events")
    # Validate full envelope before any event can change state.
    for event in events:
        if (not isinstance(event, dict) or not isinstance(event.get("event_id"), str)
                or not 1 <= len(event["event_id"]) <= 100
                or event.get("kind") not in ("validate", "depart")
                or not isinstance(event.get("trip_id"), str)
                or (event["kind"] == "validate" and not isinstance(event.get("user_id"), str))):
            reject(422, "invalid_event")
    results = []
    for event in events:
        event_id = event["event_id"]
        payload = json.dumps(event, sort_keys=True)
        old = conn.execute("SELECT payload, result FROM events WHERE id=?", (event_id,)).fetchone()
        if old:
            if old["payload"] == payload:
                results.append({**json.loads(old["result"]), "replayed": True})
            else:
                results.append({"event_id": event_id, "status": "rejected", "code": "event_id_conflict", "replayed": False})
            continue
        try:
            outcome = validate_passenger(conn, event) if event["kind"] == "validate" else depart(conn, event)
            result = {"event_id": event_id, "status": "accepted", **outcome, "replayed": False}
        except DomainError as error:
            result = {"event_id": event_id, "status": "rejected", "code": error.code, "replayed": False}
        conn.execute("INSERT INTO events VALUES (?, ?, ?)", (event_id, payload, json.dumps(result)))
        results.append(result)
    return {"results": results}
