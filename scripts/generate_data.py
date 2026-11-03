#!/usr/bin/env python3
"""Generate a fictitious longitudinal HR data set. No real people are used.

The random seed and simulation make this reproducible. The script writes the
entire set of CSV files: do not run it over files containing your own changes.
Only Python's standard library is required.
"""
from __future__ import annotations

import calendar
import csv
import math
import random
from datetime import date
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "raw"
SEED = 27102026
rng = random.Random(SEED)

# id, department, size weight, base salary (PLN/month), typical overtime,
# baseline satisfaction, departure risk adjustment
DEPTS = [
    (1, "Operations", 0.29, 6500, 20, 3.05, 0.0022),
    (2, "Customer Support", 0.20, 6200, 18, 3.15, 0.0018),
    (3, "Sales", 0.17, 8300, 15, 3.35, 0.0010),
    (4, "Technology", 0.17, 12500, 12, 3.55, 0.0000),
    (5, "Finance", 0.09, 9000, 11, 3.50, 0.0000),
    (6, "People & Culture", 0.08, 8100, 10, 3.60, 0.0000),
]
MODES = {"Hybrid": ["Hybrid", "hybrid", " HYBRID "],
         "On-site": ["On-site", "onsite", " OFFICE "],
         "Remote": ["Remote", "remote", " REMOTE "]}


def bound(x, lo, hi):
    return max(lo, min(hi, x))


def months():
    for year in (2023, 2024, 2025):
        for month in range(1, 13):
            yield date(year, month, calendar.monthrange(year, month)[1])


def iso_day(year, month):
    return date(year, month, rng.randint(1, min(28, calendar.monthrange(year, month)[1])))


def new_employee(eid, hire, dept):
    department_id, _, _, salary_base, ot_base, eng_base, _ = dept
    level = rng.choices([1, 2, 3, 4], [0.38, 0.34, 0.20, 0.08])[0]
    # Synthetic salaries are gross monthly contracted base salaries, not payroll.
    salary = round(salary_base * (1 + (level - 1) * 0.24) * rng.uniform(0.87, 1.13) / 10) * 10
    mode = rng.choices(list(MODES), [0.52, 0.35, 0.13])[0]
    if department_id in (1, 2):
        mode = rng.choices(list(MODES), [0.30, 0.61, 0.09])[0]
    age_at_hire = rng.randint(21, 55)
    return {
        "employee_id": eid, "hire_date": hire.isoformat(),
        "birth_year": hire.year - age_at_hire,
        "gender_raw": rng.choices(["F", "M", ""], [0.49, 0.50, 0.01])[0],
        "department_id": department_id, "job_level": level,
        "city": rng.choices(["Wroclaw", "Warsaw", "Krakow", "Poznan"], [0.42, 0.25, 0.19, 0.14])[0],
        "_dept": dept, "_salary": salary, "_mode": mode,
        "_prev_overtime": max(0, rng.gauss(ot_base, 6)),
        "_prev_engagement": bound(rng.gauss(eng_base, 0.55), 1, 5),
        "_individual_risk": rng.uniform(-0.0015, 0.0015),
    }


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    dept_weights = [d[2] for d in DEPTS]
    employees = []
    active = []
    for eid in range(1, 3001):
        y = rng.randint(2016, 2022)
        m = rng.randint(1, 12)
        e = new_employee(eid, iso_day(y, m), rng.choices(DEPTS, dept_weights)[0])
        employees.append(e)
        active.append(e)

    snapshot_file = OUT / "monthly_snapshots.csv"
    fields = ["month_end", "employee_id", "monthly_salary_pln", "work_mode_raw",
              "overtime_hours", "engagement_score", "performance_rating",
              "hire_flag", "exit_flag", "exit_date", "exit_type_raw", "exit_reason_raw"]
    count_rows = 0
    with snapshot_file.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, lineterminator="\n")
        writer.writeheader()
        for month_end in months():
            # Recruiting grows the workforce but does not include rehires.
            for _ in range(rng.randint(72, 100)):
                eid = len(employees) + 1
                e = new_employee(eid, iso_day(month_end.year, month_end.month), rng.choices(DEPTS, dept_weights)[0])
                employees.append(e)
                active.append(e)
            survivors = []
            for e in active:
                hire = date.fromisoformat(e["hire_date"])
                hired = int((hire.year, hire.month) == (month_end.year, month_end.month))
                dept = e["_dept"]
                # The last month's simulated conditions influence the next month's
                # probability. This is synthetic design, not real-world evidence.
                p = (0.006 + dept[6] + e["_individual_risk"]
                     + max(e["_prev_overtime"] - 8, 0) * 0.00055
                     + max(3.4 - e["_prev_engagement"], 0) * 0.0025)
                if month_end.year == 2024 and month_end.month >= 7 and dept[0] in (1, 2):
                    p += 0.0025
                p = bound(p, 0.002, 0.065)
                exited = int(rng.random() < p)
                if month_end.month == 1 and hire.year < month_end.year:
                    e["_salary"] = round(e["_salary"] * rng.uniform(1.025, 1.07) / 10) * 10
                overtime = bound(rng.gauss(dept[4], 6.8) + (2 if month_end.month in (3, 9, 12) else 0), 0, 50)
                engagement = bound(rng.gauss(dept[5] - max(overtime - 15, 0) * 0.018, 0.55), 1, 5)
                performance = rng.choices([1, 2, 3, 4, 5], [0.02, 0.10, 0.42, 0.36, 0.10])[0]
                survey = "" if rng.random() < 0.24 else f"{engagement:.1f}"
                exit_type = ""
                reason = ""
                exit_date = ""
                if exited:
                    first_day = hire.day if hired else 1
                    exit_date = date(month_end.year, month_end.month, rng.randint(first_day, month_end.day)).isoformat()
                    voluntary = rng.random() < 0.79
                    exit_type = rng.choice(["Voluntary", "VOLUNTARY", " voluntary "]) if voluntary else rng.choice(["Involuntary", "INVOLUNTARY"])
                    if voluntary and rng.random() >= 0.17:
                        reason = rng.choices(["Compensation", "Career growth", "Workload", "Personal", "Other"],
                                             [0.23, 0.26, 0.27, 0.16, 0.08])[0]
                    elif not voluntary and rng.random() >= 0.12:
                        reason = rng.choices(["Restructuring", "Performance", "Other"], [0.55, 0.35, 0.10])[0]
                else:
                    survivors.append(e)
                writer.writerow({
                    "month_end": month_end.isoformat(), "employee_id": e["employee_id"],
                    "monthly_salary_pln": e["_salary"], "work_mode_raw": rng.choice(MODES[e["_mode"]]),
                    "overtime_hours": f"{overtime:.1f}", "engagement_score": survey,
                    "performance_rating": performance, "hire_flag": hired, "exit_flag": exited,
                    "exit_date": exit_date, "exit_type_raw": exit_type, "exit_reason_raw": reason,
                })
                count_rows += 1
                e["_prev_overtime"] = overtime
                e["_prev_engagement"] = engagement
            active = survivors
    employee_fields = ["employee_id", "hire_date", "birth_year", "gender_raw", "department_id", "job_level", "city"]
    with (OUT / "employees.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=employee_fields, extrasaction="ignore", lineterminator="\n")
        writer.writeheader()
        writer.writerows(employees)
    with (OUT / "departments.csv").open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle, lineterminator="\n")
        writer.writerow(["department_id", "department_name"])
        writer.writerows((d[0], d[1]) for d in DEPTS)
    print(f"Seed: {SEED}; departments: {len(DEPTS)}; employees: {len(employees):,}; "
          f"employee-months: {count_rows:,}; final active workforce: {len(active):,}")
    print(f"Saved to {OUT}")


if __name__ == "__main__":
    main()
