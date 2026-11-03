#!/usr/bin/env python3
"""Validate the complete CSV extracts before loading them to SQL Server.

Run from anywhere: python scripts/validate_data.py
This intentionally permits missing survey scores and exit reasons. It refuses
broken keys, gaps and inconsistent employment events. Standard library only.
"""
from __future__ import annotations
import calendar
import csv
from collections import defaultdict
from datetime import date
from decimal import Decimal, InvalidOperation
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / "data" / "raw"
HEADERS = {
    "departments": ["department_id", "department_name"],
    "employees": ["employee_id", "hire_date", "birth_year", "gender_raw", "department_id", "job_level", "city"],
    "monthly_snapshots": ["month_end", "employee_id", "monthly_salary_pln", "work_mode_raw", "overtime_hours", "engagement_score", "performance_rating", "hire_flag", "exit_flag", "exit_date", "exit_type_raw", "exit_reason_raw"],
}


def records(name):
    with (DATA / f"{name}.csv").open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.DictReader(f)
        if reader.fieldnames != HEADERS[name]:
            raise ValueError(f"{name}.csv: incorrect headers: {reader.fieldnames}")
        for line, row in enumerate(reader, 2):
            if None in row or any(v is None for v in row.values()):
                raise ValueError(f"{name}.csv line {line}: incorrect number of columns")
            yield line, row


def month_index(d):
    return d.year * 12 + d.month


def validate():
    departments = {}
    for line, r in records("departments"):
        key = int(r["department_id"])
        if key in departments or not r["department_name"].strip():
            raise ValueError(f"departments.csv line {line}: duplicate key or empty department")
        departments[key] = r["department_name"].strip()
    employees = {}
    for line, r in records("employees"):
        eid = int(r["employee_id"])
        hire = date.fromisoformat(r["hire_date"])
        if eid in employees or int(r["department_id"]) not in departments:
            raise ValueError(f"employees.csv line {line}: duplicate employee or missing department")
        if int(r["birth_year"]) > hire.year or int(r["job_level"]) not in (1, 2, 3, 4):
            raise ValueError(f"employees.csv line {line}: invalid birth year or job level")
        if r["gender_raw"].strip().upper() not in ("F", "M", ""):
            raise ValueError(f"employees.csv line {line}: unsupported gender code")
        employees[eid] = hire
    seen = set()
    histories = defaultdict(list)
    all_months = set()
    missing_engagement = 0
    missing_exit_reason = 0
    exits = 0
    valid_modes = {"hybrid", "onsite", "on-site", "office", "remote"}
    try:
        for line, r in records("monthly_snapshots"):
            d = date.fromisoformat(r["month_end"])
            eid = int(r["employee_id"])
            hire = employees.get(eid)
            key = (d, eid)
            if d.day != calendar.monthrange(d.year, d.month)[1] or key in seen or hire is None or hire > d:
                raise ValueError(f"monthly_snapshots.csv line {line}: bad month, duplicate, orphan or hire date")
            seen.add(key)
            all_months.add(month_index(d))
            hf, ef = int(r["hire_flag"]), int(r["exit_flag"])
            if hf not in (0, 1) or ef not in (0, 1) or hf != int(month_index(hire) == month_index(d)):
                raise ValueError(f"monthly_snapshots.csv line {line}: invalid hire or exit flag")
            if Decimal(r["monthly_salary_pln"]) <= 0 or not (Decimal(0) <= Decimal(r["overtime_hours"]) <= Decimal(80)):
                raise ValueError(f"monthly_snapshots.csv line {line}: invalid salary or overtime")
            score = r["engagement_score"].strip()
            if not score:
                missing_engagement += 1
            elif not (Decimal(1) <= Decimal(score) <= Decimal(5)):
                raise ValueError(f"monthly_snapshots.csv line {line}: engagement outside 1–5")
            if int(r["performance_rating"]) not in (1, 2, 3, 4, 5) or r["work_mode_raw"].strip().lower() not in valid_modes:
                raise ValueError(f"monthly_snapshots.csv line {line}: invalid performance or work mode")
            exit_type = r["exit_type_raw"].strip().lower()
            if ef:
                exits += 1
                exit_date = date.fromisoformat(r["exit_date"])
                if month_index(exit_date) != month_index(d) or exit_date < hire or exit_type not in ("voluntary", "involuntary"):
                    raise ValueError(f"monthly_snapshots.csv line {line}: invalid exit date or type")
                missing_exit_reason += int(not r["exit_reason_raw"].strip())
            elif r["exit_date"].strip() or exit_type or r["exit_reason_raw"].strip():
                raise ValueError(f"monthly_snapshots.csv line {line}: exit data for non-exit")
            histories[eid].append((month_index(d), ef))
    except (InvalidOperation, TypeError) as exc:
        raise ValueError(f"Bad numeric value: {exc}") from exc
    if not all_months:
        raise ValueError("No monthly data")
    first, last = min(all_months), max(all_months)
    if all_months != set(range(first, last + 1)):
        raise ValueError("At least one month is missing from the entire extract")
    if set(histories) != set(employees):
        raise ValueError("Every employee in the complete employee file must have a snapshot")
    for eid, history in histories.items():
        history.sort()
        month_list = [item[0] for item in history]
        expected_start = max(first, month_index(employees[eid]))
        if month_list[0] != expected_start or month_list != list(range(month_list[0], month_list[-1] + 1)):
            raise ValueError(f"Employee {eid}: snapshot history starts late or contains gaps")
        exits_at = [i for i, (_, exit_flag) in enumerate(history) if exit_flag]
        if len(exits_at) > 1 or (exits_at and exits_at[0] != len(history) - 1):
            raise ValueError(f"Employee {eid}: multiple exits or snapshots after exit")
        if not exits_at and month_list[-1] != last:
            raise ValueError(f"Employee {eid}: no exit and missing later snapshots")
    return {"departments": len(departments), "employees": len(employees), "employee_months": len(seen),
            "months": len(all_months), "exits": exits, "missing_engagement": missing_engagement,
            "missing_exit_reasons": missing_exit_reason}


if __name__ == "__main__":
    try:
        result = validate()
    except (ValueError, OSError) as error:
        raise SystemExit(f"VALIDATION FAILED: {error}") from error
    print("VALIDATION PASSED")
    for key, value in result.items():
        print(f"{key}: {value:,}")
