/* 05: Workforce and turnover questions. Rates use a consistent denominator. */
USE HR_Analytics;
GO

-- Q1. In 2025, which departments had the highest overall and voluntary turnover?
-- Average headcount is the mean of each month's (opening + closing) / 2.
WITH monthly AS (
    SELECT e.department, f.month_end,
           SUM(CASE WHEN f.hire_flag = 0 THEN 1 ELSE 0 END) AS opening_headcount,
           SUM(CASE WHEN f.exit_flag = 0 THEN 1 ELSE 0 END) AS closing_headcount,
           SUM(f.exit_flag) AS exits,
           SUM(CASE WHEN f.exit_type = 'Voluntary' THEN 1 ELSE 0 END) AS voluntary_exits
    FROM analytics.vw_fact_monthly AS f
    JOIN analytics.vw_dim_employee AS e ON f.employee_id = e.employee_id
    WHERE f.month_end >= '20250101' AND f.month_end < '20260101'
    GROUP BY e.department, f.month_end
), annual AS (
    SELECT department, SUM(exits) AS exits, SUM(voluntary_exits) AS voluntary_exits,
           AVG((opening_headcount + closing_headcount) / 2.0) AS avg_headcount
    FROM monthly GROUP BY department
)
SELECT department, exits, voluntary_exits, CAST(avg_headcount AS decimal(10,2)) AS avg_headcount,
       CAST(100.0 * exits / NULLIF(avg_headcount, 0) AS decimal(6,2)) AS turnover_pct,
       CAST(100.0 * voluntary_exits / NULLIF(avg_headcount, 0) AS decimal(6,2)) AS voluntary_turnover_pct
FROM annual ORDER BY turnover_pct DESC;

-- Q2. What are the reported reasons among voluntary exits in 2025?
-- Keep 'Not reported' in the denominator; the reasons are recorded categories.
WITH reasons AS (
    SELECT exit_reason, COUNT(*) AS exits
    FROM analytics.vw_fact_monthly
    WHERE exit_type = 'Voluntary' AND month_end >= '20250101' AND month_end < '20260101'
    GROUP BY exit_reason
)
SELECT exit_reason, exits,
       CAST(100.0 * exits / NULLIF(SUM(exits) OVER (), 0) AS decimal(6,2)) AS pct_of_voluntary_exits
FROM reasons ORDER BY exits DESC;

-- Q3. Compare base pay within department and job level at the end of 2025.
-- Descriptive only: occupation, experience and hours are not fully controlled.
SELECT e.department, e.job_level, e.gender, COUNT(*) AS employees,
       CAST(AVG(f.monthly_salary_pln) AS decimal(12,2)) AS mean_base_salary_pln
FROM analytics.vw_fact_monthly AS f
JOIN analytics.vw_dim_employee AS e ON f.employee_id = e.employee_id
WHERE f.month_end = '20251231' AND f.exit_flag = 0
GROUP BY e.department, e.job_level, e.gender
HAVING COUNT(*) >= 20
ORDER BY e.department, e.job_level, e.gender;

-- Q4. Rank departments by 2025 exits (COUNT is volume, not turnover rate).
WITH counts AS (
    SELECT e.department, SUM(f.exit_flag) AS exits
    FROM analytics.vw_fact_monthly AS f
    JOIN analytics.vw_dim_employee AS e ON e.employee_id = f.employee_id
    WHERE f.month_end >= '20250101' AND f.month_end < '20260101'
    GROUP BY e.department
)
SELECT department, exits, DENSE_RANK() OVER (ORDER BY exits DESC) AS volume_rank
FROM counts ORDER BY volume_rank, department;
