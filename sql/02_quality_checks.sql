/* 02: Run AFTER loading the CSVs. Each result is a separate quality check.
   Missing engagement and exit reasons are expected; do not replace them by zero. */
USE HR_Analytics;
GO

SELECT 'departments' AS source_table, COUNT_BIG(*) AS row_count FROM stg.departments
UNION ALL SELECT 'employees', COUNT_BIG(*) FROM stg.employees
UNION ALL SELECT 'monthly_snapshots', COUNT_BIG(*) FROM stg.monthly_snapshots;

-- Critical duplicates: the result should have zero rows.
SELECT employee_id, COUNT(*) AS duplicates FROM stg.employees
GROUP BY employee_id HAVING COUNT(*) > 1;
SELECT month_end, employee_id, COUNT(*) AS duplicates FROM stg.monthly_snapshots
GROUP BY month_end, employee_id HAVING COUNT(*) > 1;

-- Foreign-key issues: the result should have zero rows.
SELECT TOP (50) s.employee_id FROM stg.monthly_snapshots AS s
LEFT JOIN stg.employees AS e ON s.employee_id = e.employee_id
WHERE e.employee_id IS NULL;
SELECT TOP (50) e.employee_id, e.department_id FROM stg.employees AS e
LEFT JOIN stg.departments AS d ON e.department_id = d.department_id
WHERE d.department_id IS NULL;

-- Critical typing and flag checks: the result should be zero.
SELECT COUNT(*) AS invalid_required_rows
FROM stg.monthly_snapshots
WHERE TRY_CONVERT(date, month_end, 23) IS NULL
   OR TRY_CONVERT(int, employee_id) IS NULL
   OR TRY_CONVERT(decimal(12,2), monthly_salary_pln) IS NULL
   OR TRY_CONVERT(decimal(5,1), overtime_hours) IS NULL
   OR TRY_CONVERT(int, hire_flag) NOT IN (0, 1) OR TRY_CONVERT(int, hire_flag) IS NULL
   OR TRY_CONVERT(int, exit_flag) NOT IN (0, 1) OR TRY_CONVERT(int, exit_flag) IS NULL;

-- Known missing data; report these counts and their denominator.
SELECT COUNT(*) AS employee_months,
       SUM(CASE WHEN NULLIF(TRIM(engagement_score), '') IS NULL THEN 1 ELSE 0 END) AS missing_engagement,
       SUM(CASE WHEN exit_flag = '1' AND NULLIF(TRIM(exit_reason_raw), '') IS NULL THEN 1 ELSE 0 END) AS exits_without_reason,
       SUM(CASE WHEN exit_flag = '1' THEN 1 ELSE 0 END) AS exits
FROM stg.monthly_snapshots;

-- Inspect inconsistent labels before mapping them in the clean views.
SELECT work_mode_raw, COUNT(*) AS rows_count FROM stg.monthly_snapshots
GROUP BY work_mode_raw ORDER BY rows_count DESC;
SELECT exit_type_raw, COUNT(*) AS rows_count FROM stg.monthly_snapshots
WHERE exit_flag = '1' GROUP BY exit_type_raw ORDER BY rows_count DESC;
