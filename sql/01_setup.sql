/* 01: Run once in SSMS. Requires permission to create databases.
   Re-running this script does not erase imported data. */
USE master;
GO
IF DB_ID(N'HR_Analytics') IS NULL
    EXEC(N'CREATE DATABASE HR_Analytics');
GO
USE HR_Analytics;
GO
IF SCHEMA_ID(N'stg') IS NULL EXEC(N'CREATE SCHEMA stg');
GO
IF SCHEMA_ID(N'analytics') IS NULL EXEC(N'CREATE SCHEMA analytics');
GO

/* Staging retains text exactly as it appears in the source CSV. */
IF OBJECT_ID(N'stg.departments', N'U') IS NULL
    CREATE TABLE stg.departments (department_id nvarchar(30) NULL, department_name nvarchar(100) NULL);
GO
IF OBJECT_ID(N'stg.employees', N'U') IS NULL
    CREATE TABLE stg.employees (
        employee_id nvarchar(30) NULL, hire_date nvarchar(30) NULL,
        birth_year nvarchar(30) NULL, gender_raw nvarchar(30) NULL,
        department_id nvarchar(30) NULL, job_level nvarchar(30) NULL, city nvarchar(100) NULL
    );
GO
IF OBJECT_ID(N'stg.monthly_snapshots', N'U') IS NULL
    CREATE TABLE stg.monthly_snapshots (
        month_end nvarchar(30) NULL, employee_id nvarchar(30) NULL,
        monthly_salary_pln nvarchar(30) NULL, work_mode_raw nvarchar(60) NULL,
        overtime_hours nvarchar(30) NULL, engagement_score nvarchar(30) NULL,
        performance_rating nvarchar(30) NULL, hire_flag nvarchar(30) NULL,
        exit_flag nvarchar(30) NULL, exit_date nvarchar(30) NULL,
        exit_type_raw nvarchar(60) NULL, exit_reason_raw nvarchar(100) NULL
    );
GO
