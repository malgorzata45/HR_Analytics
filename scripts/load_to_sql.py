#!/usr/bin/env python3
"""Replace this project's staging extracts in one SQL Server transaction.

The CSVs must represent the COMPLETE history, not just the latest month.
Windows authentication; password is never stored. Old staging data remain if
validation or loading fails. See docs/01_START_TUTAJ.md for full instructions.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import shutil
import sys
import tempfile
from pathlib import Path
import validate_data as data

CHUNK = 2000


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", required=True, help=r"SSMS server name, e.g. localhost\SQLEXPRESS")
    parser.add_argument("--if-changed", action="store_true", help="Skip reload when all source hashes match the last successful load on this server")
    args = parser.parse_args()
    # Work from one local copy: validation and loading see identical bytes.
    with tempfile.TemporaryDirectory(prefix="hr_analytics_") as tmp:
        source = data.DATA
        snapshot = Path(tmp)
        for name in data.HEADERS:
            shutil.copy2(source / f"{name}.csv", snapshot / f"{name}.csv")
        data.DATA = snapshot
        hashes = {}
        for name in data.HEADERS:
            h = hashlib.sha256()
            with (snapshot / f"{name}.csv").open("rb") as handle:
                for chunk in iter(lambda: handle.read(1024 * 1024), b""):
                    h.update(chunk)
            hashes[name] = h.hexdigest()
        signature = {"server": args.server, "sha256": hashes}
        manifest = data.ROOT / "output" / ".last_successful_load.json"
        if args.if_changed and manifest.exists():
            try:
                if json.loads(manifest.read_text(encoding="utf-8")) == signature:
                    print("No source changes since last successful load; skipping.")
                    return
            except (ValueError, OSError):
                pass  # An unreadable manifest must never prevent a load.
        perform_load(args, signature, manifest)


def perform_load(args, signature, manifest):
    result = data.validate()  # gate before opening a transaction
    print("CSV validation passed:", result, flush=True)
    try:
        import pyodbc
    except ImportError:
        raise SystemExit('Missing pyodbc. Run: py -m pip install pyodbc')
    available = pyodbc.drivers()
    driver = next((x for x in ("ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server") if x in available), None)
    if not driver:
        raise SystemExit(f"Install Microsoft ODBC Driver 17 or 18 for SQL Server. Detected: {available}")
    connection_string = (f"DRIVER={{{driver}}};SERVER={args.server};DATABASE=HR_Analytics;"
                         "Trusted_Connection=yes;TrustServerCertificate=yes;")
    conn = pyodbc.connect(connection_string, autocommit=False, timeout=30)
    try:
        cursor = conn.cursor()
        # Dependency order leaves old dataset recoverable with rollback.
        for name in ("monthly_snapshots", "employees", "departments"):
            cursor.execute(f"DELETE FROM stg.{name}")
        for name in ("departments", "employees", "monthly_snapshots"):
            columns = data.HEADERS[name]  # fixed, trusted names; no user SQL
            placeholders = ",".join("?" for _ in columns)
            statement = f"INSERT INTO stg.{name} ({','.join(columns)}) VALUES ({placeholders})"
            cursor.fast_executemany = True
            batch = []
            for _, row in data.records(name):
                batch.append(tuple(row[c] if row[c] != "" else None for c in columns))
                if len(batch) == CHUNK:
                    cursor.executemany(statement, batch)
                    batch.clear()
            if batch:
                cursor.executemany(statement, batch)
            cursor.execute(f"SELECT COUNT_BIG(*) FROM stg.{name}")
            expected = result["employee_months" if name == "monthly_snapshots" else name]
            count = cursor.fetchone()[0]
            if count != expected:
                raise RuntimeError(f"Row count mismatch in {name}: {count} != {expected}")
            print(f"Loaded {name}: {count:,}", flush=True)
        conn.commit()
        try:
            manifest.parent.mkdir(exist_ok=True)
            tmp_manifest = manifest.with_suffix(".tmp")
            tmp_manifest.write_text(json.dumps(signature, indent=2), encoding="utf-8")
            tmp_manifest.replace(manifest)
        except OSError as exc:
            # SQL was committed already; a missing cache only causes a later reload.
            print(f"Load committed, but change-detection cache could not be saved: {exc}", file=sys.stderr)
        print("SUCCESS: complete extract committed. Refresh the Power BI model to see it.")
    except Exception:
        conn.rollback()
        print("Load failed: transaction rolled back; previous staging data preserved.", file=sys.stderr)
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
