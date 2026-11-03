/* ======================================================================
   08 | ANALIZA ZAAWANSOWANA: OKNA, RANKING, MEDIANA, KOHORTA
   ======================================================================
   WYMAGANIA: pliki 01–07 po załadowaniu danych.
   Uruchamiaj każdą sekcję osobno, łącznie z jej CTE i końcowym SELECT.
   Wyniki pochodzą z danych SYNTETYCZNYCH i nie dowodzą przyczynowości.
   ====================================================================== */
USE HR_Analytics;
GO

/* 08.1. Trend: zmiana zatrudnienia m/m oraz rotacja z ostatnich 3 miesięcy.
   LAG pobiera poprzedni wiersz. SUM i AVG z OVER tworzą okno bieżącego
   oraz dwóch poprzednich miesięcy. Okna liczymy dla CAŁEJ historii, a dopiero
   na końcu pokazujemy 2025: dzięki temu styczeń może korzystać z końca 2024.
   Rotacja 3M = SUM(odejść z 3 miesięcy) / AVG(miesięcznego średniego stanu).
   NIE sumujemy ani nie uśredniamy trzech procentów miesięcznych.
   Wynik 3M pokazujemy tylko, jeśli istnieją 3 kolejne miesiące. */
WITH windowed AS (
    SELECT
        month_end, opening_headcount, hires, exits, closing_headcount,
        average_headcount, monthly_turnover_pct,
        LAG(closing_headcount) OVER (ORDER BY month_end) AS previous_closing,
        LAG(month_end, 2) OVER (ORDER BY month_end) AS month_two_rows_before,
        COUNT(*) OVER (ORDER BY month_end ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS months_in_window,
        SUM(exits) OVER (ORDER BY month_end ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS exits_3m,
        AVG(average_headcount) OVER (ORDER BY month_end ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS avg_headcount_3m
    FROM analytics.vw_workforce_monthly_kpi
)
SELECT
    month_end, opening_headcount, hires, exits, closing_headcount,
    previous_closing,
    closing_headcount - previous_closing AS headcount_change_mom,
    monthly_turnover_pct,
    CASE WHEN months_in_window = 3 AND DATEDIFF(month, month_two_rows_before, month_end) = 2
         THEN CAST(100.0 * exits_3m / NULLIF(avg_headcount_3m, 0) AS decimal(8,2))
         ELSE NULL END AS turnover_last_3_months_pct
FROM windowed
WHERE month_end >= '20250101' AND month_end < '20260101'
ORDER BY month_end;

/* 08.2. Ranking działów według rocznej ROTACJI, nie samej liczby odejść.
   DENSE_RANK daje ten sam ranking działom z jednakowym wskaźnikiem.
   W podanym zbiorze każdy dział ma dane we wszystkich 12 miesiącach 2025.
   Przy zmianie danych sprawdź months_present; brak miesiąca wymaga wyjaśnienia. */
WITH department_year AS (
    SELECT
        department,
        COUNT(*) AS months_present,
        SUM(exits) AS exits,
        SUM(voluntary_exits) AS voluntary_exits,
        AVG(average_headcount) AS avg_headcount
    FROM analytics.vw_department_monthly_kpi
    WHERE month_end >= '20250101' AND month_end < '20260101'
    GROUP BY department
), rates AS (
    SELECT department, months_present, exits, voluntary_exits, avg_headcount,
           100.0 * exits / NULLIF(avg_headcount, 0) AS turnover_pct,
           100.0 * voluntary_exits / NULLIF(avg_headcount, 0) AS voluntary_turnover_pct
    FROM department_year
)
SELECT
    DENSE_RANK() OVER (ORDER BY turnover_pct DESC) AS turnover_rank,
    department, months_present, exits, voluntary_exits,
    CAST(avg_headcount AS decimal(12,2)) AS avg_headcount,
    CAST(turnover_pct AS decimal(8,2)) AS turnover_pct,
    CAST(voluntary_turnover_pct AS decimal(8,2)) AS voluntary_turnover_pct
FROM rates
ORDER BY turnover_rank, department;

/* 08.3. Mediana i średnia wynagrodzeń według działu na 31.12.2025.
   PERCENTILE_CONT jest funkcją okna: nie redukuje wierszy, dlatego wyniki
   dla każdego działu sprowadzamy do jednego wiersza przez DISTINCT.
   To wynagrodzenie zasadnicze, nie koszt pracodawcy; analiza jest opisowa. */
WITH active_employees AS (
    SELECT e.department, f.monthly_salary_pln
    FROM analytics.vw_fact_monthly AS f
    INNER JOIN analytics.vw_dim_employee AS e ON e.employee_id = f.employee_id
    WHERE f.month_end = '20251231' AND f.exit_flag = 0
), stats AS (
    SELECT department,
           COUNT(*) OVER (PARTITION BY department) AS employees,
           AVG(monthly_salary_pln) OVER (PARTITION BY department) AS avg_salary,
           PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY monthly_salary_pln)
               OVER (PARTITION BY department) AS median_salary
    FROM active_employees
)
SELECT DISTINCT department, employees,
       CAST(avg_salary AS decimal(12,2)) AS avg_base_pln,
       CAST(median_salary AS decimal(12,2)) AS median_base_pln
FROM stats
ORDER BY department;

/* 08.4. Jedna kohorta, liczebności, różnica ryzyka i przybliżony 95% CI.
   Ziarno: osoba aktywna 30.06.2024; wynik: dowolne odejście lip–wrz 2024.
   Poniższy przedział dla różnicy to przybliżenie Walda, bez korekt.
   Test Fishera z dokładnym dwustronnym p oblicza osobny skrypt Python;
   samo SQL poniżej NIE oblicza p i NIE udowadnia przyczynowości. */
WITH group_counts AS (
    SELECT
        SUM(CASE WHEN overtime_group = 'Low (<10 h)' THEN 1 ELSE 0 END) AS low_n,
        SUM(CASE WHEN overtime_group = 'Low (<10 h)' THEN exited_in_3_months ELSE 0 END) AS low_exits,
        SUM(CASE WHEN overtime_group = 'High (20+ h)' THEN 1 ELSE 0 END) AS high_n,
        SUM(CASE WHEN overtime_group = 'High (20+ h)' THEN exited_in_3_months ELSE 0 END) AS high_exits
    FROM analytics.vw_cohort_june_2024
), rates AS (
    SELECT *,
        CAST(low_exits AS float) / NULLIF(low_n, 0) AS p_low,
        CAST(high_exits AS float) / NULLIF(high_n, 0) AS p_high
    FROM group_counts
), estimate AS (
    SELECT *, p_high - p_low AS difference,
        SQRT(p_high * (1.0 - p_high) / NULLIF(high_n, 0)
           + p_low * (1.0 - p_low) / NULLIF(low_n, 0)) AS standard_error
    FROM rates
)
SELECT low_n, low_exits, high_n, high_exits,
       CAST(100.0 * p_low AS decimal(8,2)) AS low_exit_pct,
       CAST(100.0 * p_high AS decimal(8,2)) AS high_exit_pct,
       CAST(100.0 * difference AS decimal(8,2)) AS difference_pp,
       CAST(100.0 * (difference - 1.96 * standard_error) AS decimal(8,2)) AS ci95_low_pp,
       CAST(100.0 * (difference + 1.96 * standard_error) AS decimal(8,2)) AS ci95_high_pp
FROM estimate;

/* 08.5. Rozbij porównanie na działy. To nie jest kontrola wszystkich
   czynników zakłócających. Przy małych grupach odsetki są mniej stabilne.
   Operations w tym zbiorze ma kierunek różnicy inny niż wynik ogólny. */
SELECT e.department, c.overtime_group, COUNT(*) AS people,
       SUM(c.exited_in_3_months) AS exits,
       CAST(100.0 * SUM(c.exited_in_3_months) / NULLIF(COUNT(*), 0)
            AS decimal(8,2)) AS exit_pct
FROM analytics.vw_cohort_june_2024 AS c
INNER JOIN analytics.vw_dim_employee AS e ON e.employee_id = c.employee_id
WHERE c.overtime_group IN ('Low (<10 h)', 'High (20+ h)')
GROUP BY e.department, c.overtime_group
ORDER BY e.department, c.overtime_group;
