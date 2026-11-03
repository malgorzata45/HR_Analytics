/* ======================================================================
   07 | WARSTWA RAPORTOWA: DWIE TABELE LOGICZNE W POSTACI WIDOKÓW
   ======================================================================
   WYMAGANIA: baza HR_Analytics, załadowane CSV oraz wykonany plik 03.
   KOLEJNOŚĆ: uruchom w SSMS cały plik; potem uruchom pliki 08 i 09.

   CEL:
   - Jeden wiersz miesięczny dla działu oraz jeden wiersz dla całej firmy.
   - Obliczenia są scentralizowane i można je wykorzystać w wielu analizach.
   - To widoki: nie zastępują stg i nie zapisują osobnej kopii danych.

   ZIARNO: miesiąc + dział (pierwszy widok); miesiąc (drugi widok).
   WAŻNE: średnie zatrudnienie = (stan początku + stan końca) / 2.
   Źródło zawiera również osoby zatrudnione tylko przez część miesiąca.
   Sam wskaźnik miesięczny nie jest rocznym wskaźnikiem rotacji.
   ====================================================================== */
USE HR_Analytics;
GO

/* 07.1. Najpierw grupujemy fakty według miesiąca i działu.
   JOIN dodaje dział na podstawie employee_id z widoku pracowników.
   Wyrażenia CASE zliczają osoby, dla których warunek jest prawdziwy.
   Nazwy kolumn i format danych są po angielsku, jak w repozytorium. */
CREATE OR ALTER VIEW analytics.vw_department_monthly_kpi AS
WITH monthly AS (
    SELECT
        f.month_end,
        e.department,
        COUNT_BIG(*) AS employee_months,
        SUM(CASE WHEN f.hire_flag = 0 THEN 1 ELSE 0 END) AS opening_headcount,
        SUM(f.hire_flag) AS hires,
        SUM(f.exit_flag) AS exits,
        SUM(CASE WHEN f.exit_type = 'Voluntary' THEN 1 ELSE 0 END) AS voluntary_exits,
        SUM(CASE WHEN f.exit_flag = 0 THEN 1 ELSE 0 END) AS closing_headcount,
        COUNT(f.engagement_score) AS survey_responses,
        AVG(f.engagement_score) AS avg_engagement_available,
        AVG(f.overtime_hours) AS avg_overtime_present
    FROM analytics.vw_fact_monthly AS f
    INNER JOIN analytics.vw_dim_employee AS e
        ON f.employee_id = e.employee_id
    GROUP BY f.month_end, e.department
)
SELECT
    month_end, department, employee_months,
    opening_headcount, hires, exits, voluntary_exits, closing_headcount,
    CAST((opening_headcount + closing_headcount) / 2.0 AS decimal(12,2)) AS average_headcount,
    CAST(100.0 * exits / NULLIF((opening_headcount + closing_headcount) / 2.0, 0)
         AS decimal(8,2)) AS monthly_turnover_pct,
    survey_responses,
    CAST(100.0 * survey_responses / NULLIF(employee_months, 0) AS decimal(8,2)) AS survey_coverage_pct,
    CAST(avg_engagement_available AS decimal(5,2)) AS avg_engagement_available,
    CAST(avg_overtime_present AS decimal(7,2)) AS avg_overtime_present
FROM monthly;
GO

/* 07.2. Agregujemy wyniki działów do poziomu firmy.
   SUM(average_headcount) jest prawidłowe, bo działy są rozłączne.
   Te wyniki opisują cały miesiąc, również osoby, które w nim odeszły.
   W raporcie Power BI średnie nadgodziny dotyczą osób aktywnych na KONIEC
   ostatniego miesiąca; nie porównuj tych definicji jak identycznych. */
CREATE OR ALTER VIEW analytics.vw_workforce_monthly_kpi AS
SELECT
    month_end,
    SUM(employee_months) AS employee_months,
    SUM(opening_headcount) AS opening_headcount,
    SUM(hires) AS hires,
    SUM(exits) AS exits,
    SUM(voluntary_exits) AS voluntary_exits,
    SUM(closing_headcount) AS closing_headcount,
    SUM(average_headcount) AS average_headcount,
    CAST(100.0 * SUM(exits) / NULLIF(SUM(average_headcount), 0)
         AS decimal(8,2)) AS monthly_turnover_pct
FROM analytics.vw_department_monthly_kpi
GROUP BY month_end;
GO

-- 07.3. Obejrzyj wyniki. Oczekujemy: 36 miesięcy, 216 wierszy dział-miesiąc.
SELECT COUNT(*) AS company_months FROM analytics.vw_workforce_monthly_kpi;
SELECT COUNT(*) AS department_months FROM analytics.vw_department_monthly_kpi;
SELECT * FROM analytics.vw_workforce_monthly_kpi ORDER BY month_end;
SELECT * FROM analytics.vw_department_monthly_kpi
WHERE month_end = '20251231' ORDER BY department;
