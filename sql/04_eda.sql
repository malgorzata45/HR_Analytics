/* 04: Exploratory analysis. Execute each section and interpret it. */
USE HR_Analytics;
GO

-- Snapshot coverage and overall event counts.
SELECT MIN(month_end) AS first_month, MAX(month_end) AS last_month,
       COUNT(DISTINCT month_end) AS months, COUNT(*) AS employee_months,
       COUNT(DISTINCT employee_id) AS employees_observed,
       SUM(hire_flag) AS hires, SUM(exit_flag) AS exits
FROM analytics.vw_fact_monthly;

-- Headcount reconciliation: opening + hires - exits = closing.
-- Everyone who left mid-month is included in that month's snapshot.
WITH monthly AS (
    SELECT month_end,
           SUM(CASE WHEN hire_flag = 0 THEN 1 ELSE 0 END) AS opening_headcount,
           SUM(hire_flag) AS hires, SUM(exit_flag) AS exits,
           SUM(CASE WHEN exit_flag = 0 THEN 1 ELSE 0 END) AS closing_headcount
    FROM analytics.vw_fact_monthly
    GROUP BY month_end
)
SELECT *, opening_headcount + hires - exits - closing_headcount AS reconciliation_difference,
       LAG(closing_headcount) OVER (ORDER BY month_end) AS previous_month_closing,
       CAST(100.0 * exits / NULLIF((opening_headcount + closing_headcount) / 2.0, 0) AS decimal(7,2)) AS monthly_turnover_pct
FROM monthly ORDER BY month_end;

-- Missing survey scores by department; COUNT(column) excludes NULL.
SELECT e.department, COUNT(*) AS employee_months,
       COUNT(f.engagement_score) AS scores_available,
       SUM(CASE WHEN f.engagement_score IS NULL THEN 1 ELSE 0 END) AS scores_missing,
       CAST(100.0 * COUNT(f.engagement_score) / NULLIF(COUNT(*), 0) AS decimal(7,2)) AS survey_coverage_pct,
       CAST(AVG(f.engagement_score) AS decimal(4,2)) AS avg_available_score
FROM analytics.vw_fact_monthly AS f
JOIN analytics.vw_dim_employee AS e ON f.employee_id = e.employee_id
GROUP BY e.department ORDER BY survey_coverage_pct;

-- Latest month salary and work patterns. Salary is contracted base, not payroll cost.
SELECT e.department, COUNT(*) AS employees_present_in_month,
       CAST(AVG(f.monthly_salary_pln) AS decimal(12,2)) AS avg_monthly_base_pln,
       CAST(AVG(f.overtime_hours) AS decimal(6,2)) AS avg_overtime_hours,
       CAST(AVG(f.engagement_score) AS decimal(4,2)) AS avg_available_engagement
FROM analytics.vw_fact_monthly AS f
JOIN analytics.vw_dim_employee AS e ON f.employee_id = e.employee_id
WHERE f.month_end = (SELECT MAX(month_end) FROM analytics.vw_fact_monthly)
  AND f.exit_flag = 0
GROUP BY e.department ORDER BY avg_overtime_hours DESC;
