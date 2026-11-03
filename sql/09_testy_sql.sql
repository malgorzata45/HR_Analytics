/* ======================================================================
   09 | TESTY JAKOŚCI: INWARIANTY I KONTROLE KOŃCOWE
   ======================================================================
   WYMAGANIA: pliki 01–07 po załadowaniu danych.
   Każde zapytanie powinno zwrócić zero NIEPRAWIDŁOWYCH wierszy albo PASS.
   Kontrole dotyczą logiki i integralności danych, nie gwarantują prawdziwości
   historii HR. Dla analizy kohorty kompletność follow-up jest obowiązkowa.
   ====================================================================== */
USE HR_Analytics;
GO

/* 09.1. Każda osoba ma maksymalnie jeden rekord w danym miesiącu. */
SELECT employee_id, month_end, COUNT(*) AS row_count
FROM analytics.vw_fact_monthly
GROUP BY employee_id, month_end
HAVING COUNT(*) > 1;

/* 09.2. Każda osoba w fakcie ma odpowiadający rekord w wymiarze. */
SELECT DISTINCT f.employee_id
FROM analytics.vw_fact_monthly AS f
LEFT JOIN analytics.vw_dim_employee AS e ON f.employee_id = e.employee_id
WHERE e.employee_id IS NULL;

/* 09.3. Bilanse i ciągłość miesięcy. Wynik: same zera i PASS.
   W pierwszym miesiącu brak poprzedniego wyniku jest prawidłowy. */
WITH checks AS (
    SELECT month_end, opening_headcount, hires, exits, closing_headcount,
           LAG(closing_headcount) OVER (ORDER BY month_end) AS previous_closing,
           LAG(month_end) OVER (ORDER BY month_end) AS previous_month
    FROM analytics.vw_workforce_monthly_kpi
)
SELECT month_end, opening_headcount, hires, exits, closing_headcount,
       opening_headcount + hires - exits - closing_headcount AS balance_difference,
       previous_closing,
       CASE WHEN opening_headcount + hires - exits <> closing_headcount THEN 'FAIL'
            WHEN previous_closing IS NOT NULL AND opening_headcount <> previous_closing THEN 'FAIL'
            WHEN previous_month IS NOT NULL AND DATEDIFF(month, previous_month, month_end) <> 1 THEN 'FAIL'
            ELSE 'PASS' END AS result
FROM checks ORDER BY month_end;

/* 09.4. Nieprawidłowe wartości wymagające analizy. Każda liczba powinna być 0.
   Brak engagement_score jest dozwolony; ocena dostępna powinna być 1–5. */
SELECT
    SUM(CASE WHEN month_end IS NULL OR month_end <> EOMONTH(month_end) THEN 1 ELSE 0 END) AS invalid_month,
    SUM(CASE WHEN employee_id IS NULL THEN 1 ELSE 0 END) AS missing_employee_id,
    SUM(CASE WHEN monthly_salary_pln IS NULL OR monthly_salary_pln <= 0 THEN 1 ELSE 0 END) AS invalid_salary,
    SUM(CASE WHEN overtime_hours IS NULL OR overtime_hours < 0 THEN 1 ELSE 0 END) AS invalid_overtime,
    SUM(CASE WHEN engagement_score IS NOT NULL AND engagement_score NOT BETWEEN 1 AND 5 THEN 1 ELSE 0 END) AS invalid_engagement,
    SUM(CASE WHEN hire_flag IS NULL OR hire_flag NOT IN (0,1) THEN 1 ELSE 0 END) AS invalid_hire_flag,
    SUM(CASE WHEN exit_flag IS NULL OR exit_flag NOT IN (0,1) THEN 1 ELSE 0 END) AS invalid_exit_flag,
    SUM(CASE WHEN exit_flag = 1 AND exit_type IS NULL THEN 1 ELSE 0 END) AS exits_without_type
FROM analytics.vw_fact_monthly;

/* 09.5. KOMPLETNOŚĆ OBSERWACJI KOHORTY.
   Osoba aktywna na koniec czerwca powinna wystąpić w lipcu. Jeżeli nie
   odeszła w lipcu, powinna wystąpić w sierpniu; jeżeli nie odeszła do końca
   sierpnia, powinna wystąpić we wrześniu. Brak wyniku ≠ brak odejścia.
   Oczekujemy 0 wierszy. Najpierw uruchom test duplikatów 09.1. */
WITH observation AS (
    SELECT c.employee_id,
        MAX(CASE WHEN f.month_end = '20240731' THEN 1 ELSE 0 END) AS observed_jul,
        MAX(CASE WHEN f.month_end = '20240731' AND f.exit_flag = 1 THEN 1 ELSE 0 END) AS exit_jul,
        MAX(CASE WHEN f.month_end = '20240831' THEN 1 ELSE 0 END) AS observed_aug,
        MAX(CASE WHEN f.month_end = '20240831' AND f.exit_flag = 1 THEN 1 ELSE 0 END) AS exit_aug,
        MAX(CASE WHEN f.month_end = '20240930' THEN 1 ELSE 0 END) AS observed_sep
    FROM analytics.vw_cohort_june_2024 AS c
    LEFT JOIN analytics.vw_fact_monthly AS f
        ON f.employee_id = c.employee_id
       AND f.month_end >= '20240701' AND f.month_end < '20241001'
    GROUP BY c.employee_id
)
SELECT employee_id, observed_jul, exit_jul, observed_aug, exit_aug, observed_sep
FROM observation
WHERE observed_jul = 0
   OR (exit_jul = 0 AND observed_aug = 0)
   OR (exit_jul = 0 AND exit_aug = 0 AND observed_sep = 0);

/* 09.6. Kontrola konkretnych wartości oryginalnej paczki danych.
   Po świadomej zmianie zbioru wartości mogą się zmienić: porównaj z nową
   wersją danych; nie poprawiaj wyniku na siłę. */
SELECT 'cohort_count_original_extract' AS check_name, COUNT(*) AS actual_value,
       3770 AS expected_value,
       CASE WHEN COUNT(*) = 3770 THEN 'PASS' ELSE 'REVIEW DATA VERSION' END AS result
FROM analytics.vw_cohort_june_2024
UNION ALL
SELECT 'cohort_exits_original_extract', SUM(exited_in_3_months), 180,
       CASE WHEN SUM(exited_in_3_months) = 180 THEN 'PASS' ELSE 'REVIEW DATA VERSION' END
FROM analytics.vw_cohort_june_2024;
