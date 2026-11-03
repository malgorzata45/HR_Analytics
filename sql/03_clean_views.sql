/* 03: Clean without overwriting the source. Run AFTER 01_setup.sql. */
USE HR_Analytics;
GO
CREATE OR ALTER VIEW analytics.vw_dim_employee AS
SELECT TRY_CONVERT(int, e.employee_id) AS employee_id,
       TRY_CONVERT(date, e.hire_date, 23) AS hire_date,
       TRY_CONVERT(int, e.birth_year) AS birth_year,
       CASE UPPER(TRIM(e.gender_raw)) WHEN 'F' THEN 'Female' WHEN 'M' THEN 'Male'
            ELSE 'Unknown' END AS gender,
       TRY_CONVERT(int, e.department_id) AS department_id,
       TRIM(d.department_name) AS department,
       TRY_CONVERT(int, e.job_level) AS job_level,
       TRIM(e.city) AS city
FROM stg.employees AS e
INNER JOIN stg.departments AS d ON e.department_id = d.department_id;
GO
CREATE OR ALTER VIEW analytics.vw_fact_monthly AS
SELECT TRY_CONVERT(date, month_end, 23) AS month_end,
       TRY_CONVERT(int, employee_id) AS employee_id,
       TRY_CONVERT(decimal(12,2), monthly_salary_pln) AS monthly_salary_pln,
       CASE LOWER(TRIM(work_mode_raw)) WHEN 'hybrid' THEN 'Hybrid'
            WHEN 'onsite' THEN 'On-site' WHEN 'on-site' THEN 'On-site'
            WHEN 'office' THEN 'On-site' WHEN 'remote' THEN 'Remote'
            ELSE 'Unknown' END AS work_mode,
       TRY_CONVERT(decimal(5,1), overtime_hours) AS overtime_hours,
       TRY_CONVERT(decimal(3,1), NULLIF(TRIM(engagement_score), '')) AS engagement_score,
       TRY_CONVERT(int, performance_rating) AS performance_rating,
       TRY_CONVERT(int, hire_flag) AS hire_flag,
       TRY_CONVERT(int, exit_flag) AS exit_flag,
       TRY_CONVERT(date, NULLIF(TRIM(exit_date), ''), 23) AS exit_date,
       CASE LOWER(TRIM(exit_type_raw)) WHEN 'voluntary' THEN 'Voluntary'
            WHEN 'involuntary' THEN 'Involuntary' ELSE NULL END AS exit_type,
       CASE WHEN TRY_CONVERT(int, exit_flag) = 1
            THEN COALESCE(NULLIF(TRIM(exit_reason_raw), ''), 'Not reported')
            ELSE NULL END AS exit_reason
FROM stg.monthly_snapshots;
GO
CREATE OR ALTER VIEW analytics.vw_dim_month AS
SELECT DISTINCT month_end, YEAR(month_end) AS calendar_year,
       MONTH(month_end) AS month_number,
       CONVERT(char(7), month_end, 126) AS year_month
FROM analytics.vw_fact_monthly
WHERE month_end IS NOT NULL;
GO

/* Fixed cohort for Power BI: active in June 2024, outcome July–September.
   Deliberately has no relationship to the monthly date slicer. */
CREATE OR ALTER VIEW analytics.vw_cohort_june_2024 AS
WITH baseline AS (
    SELECT employee_id, overtime_hours,
           CASE WHEN overtime_hours < 10 THEN 'Low (<10 h)'
                WHEN overtime_hours >= 20 THEN 'High (20+ h)'
                ELSE 'Medium (10-<20 h)' END AS overtime_group
    FROM analytics.vw_fact_monthly
    WHERE month_end = '20240630' AND exit_flag = 0
)
SELECT b.employee_id, b.overtime_hours, b.overtime_group,
       MAX(CASE WHEN f.exit_flag = 1 THEN 1 ELSE 0 END) AS exited_in_3_months
FROM baseline AS b
LEFT JOIN analytics.vw_fact_monthly AS f ON f.employee_id = b.employee_id
    AND f.month_end >= '20240701' AND f.month_end < '20241001'
GROUP BY b.employee_id, b.overtime_hours, b.overtime_group;
GO
