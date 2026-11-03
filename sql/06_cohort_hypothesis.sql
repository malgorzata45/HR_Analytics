/* 06: One baseline per person; exposure measured before the outcome.
   Cohort = active at 2024-06-30. Outcome = any exit Jul–Sep 2024.
   This comparison is exploratory, not a causal estimate. */
USE HR_Analytics;
GO

WITH baseline AS (
    SELECT f.employee_id, f.overtime_hours, f.engagement_score, e.department,
           CASE WHEN f.overtime_hours < 10 THEN 'Low (<10 h)'
                WHEN f.overtime_hours >= 20 THEN 'High (20+ h)'
                ELSE 'Medium (10–<20 h)' END AS overtime_group
    FROM analytics.vw_fact_monthly AS f
    JOIN analytics.vw_dim_employee AS e ON f.employee_id = e.employee_id
    WHERE f.month_end = '20240630' AND f.exit_flag = 0
), outcome AS (
    SELECT b.employee_id, b.department, b.overtime_group,
           MAX(CASE WHEN f.exit_flag = 1 THEN 1 ELSE 0 END) AS exited_in_3_months
    FROM baseline AS b
    LEFT JOIN analytics.vw_fact_monthly AS f ON f.employee_id = b.employee_id
         AND f.month_end >= '20240701' AND f.month_end < '20241001'
    GROUP BY b.employee_id, b.department, b.overtime_group
)
SELECT overtime_group, COUNT(*) AS employees, SUM(exited_in_3_months) AS exits,
       CAST(100.0 * SUM(exited_in_3_months) / NULLIF(COUNT(*), 0) AS decimal(7,2)) AS exit_pct
FROM outcome GROUP BY overtime_group ORDER BY exit_pct DESC;

-- Q5. Stratify the same comparison by department. Counts must be reported.
WITH baseline AS (
    SELECT f.employee_id, e.department,
           CASE WHEN f.overtime_hours < 10 THEN 'Low (<10 h)'
                WHEN f.overtime_hours >= 20 THEN 'High (20+ h)' ELSE 'Medium' END AS overtime_group
    FROM analytics.vw_fact_monthly AS f
    JOIN analytics.vw_dim_employee AS e ON f.employee_id = e.employee_id
    WHERE f.month_end = '20240630' AND f.exit_flag = 0
), outcome AS (
    SELECT b.employee_id, b.department, b.overtime_group,
           MAX(CASE WHEN f.exit_flag = 1 THEN 1 ELSE 0 END) AS exited
    FROM baseline AS b
    LEFT JOIN analytics.vw_fact_monthly AS f ON f.employee_id = b.employee_id
         AND f.month_end >= '20240701' AND f.month_end < '20241001'
    GROUP BY b.employee_id, b.department, b.overtime_group
)
SELECT department, overtime_group, COUNT(*) AS employees, SUM(exited) AS exits,
       CAST(100.0 * SUM(exited) / NULLIF(COUNT(*), 0) AS decimal(7,2)) AS exit_pct
FROM outcome WHERE overtime_group IN ('Low (<10 h)', 'High (20+ h)')
GROUP BY department, overtime_group ORDER BY department, overtime_group;

-- Q6. Pearson correlation between overtime and AVAILABLE survey scores in June.
-- A NULL survey response is excluded, never imputed with zero.
WITH observations AS (
    SELECT CAST(overtime_hours AS float) AS x, CAST(engagement_score AS float) AS y
    FROM analytics.vw_fact_monthly
    WHERE month_end = '20240630' AND exit_flag = 0 AND engagement_score IS NOT NULL
), means AS (SELECT AVG(x) AS mean_x, AVG(y) AS mean_y FROM observations)
SELECT COUNT(*) AS paired_observations,
       SUM((o.x - m.mean_x) * (o.y - m.mean_y)) /
           NULLIF(SQRT(SUM(POWER(o.x - m.mean_x, 2)) * SUM(POWER(o.y - m.mean_y, 2))), 0) AS pearson_r
FROM observations AS o CROSS JOIN means AS m;
