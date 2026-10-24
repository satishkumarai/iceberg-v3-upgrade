--------------------------------------------------------------------------------
-- test_preflight.sql
-- Assertions for Phase 1 pre-flight output
--
-- Run after 01_preflight_checks.sql to validate the results programmatically.
-- Each query returns PASS or FAIL. Any FAIL is a blocker.
--------------------------------------------------------------------------------

SET source_fqn = $iceberg_db || '.' || $iceberg_schema || '.' || $iceberg_table;

-- Assert: table exists and is Iceberg
SHOW TABLES LIKE $iceberg_table IN SCHEMA IDENTIFIER($iceberg_db || '.' || $iceberg_schema);

SELECT
    CASE WHEN COUNT(*) = 1 THEN 'PASS' ELSE 'FAIL' END AS table_exists,
    'Table must exist in the specified schema' AS assertion
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "is_iceberg" = 'YES';

-- Assert: current version is 2
SHOW PARAMETERS LIKE 'ICEBERG_VERSION' IN TABLE IDENTIFIER($source_fqn);

SELECT
    CASE
        WHEN "value"::INT = 2 THEN 'PASS'
        ELSE 'FAIL'
    END AS version_is_2,
    'Table must be Iceberg v2 before upgrade' AS assertion
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Assert: Time Travel retention >= 1 day
SHOW TABLES LIKE $iceberg_table IN SCHEMA IDENTIFIER($iceberg_db || '.' || $iceberg_schema);

SELECT
    CASE
        WHEN "retention_time"::INT >= 1 THEN 'PASS'
        ELSE 'FAIL'
    END AS retention_adequate,
    'Time Travel retention must be >= 1 day for rollback' AS assertion,
    "retention_time" AS actual_retention_days
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Assert: current role has ownership or sufficient privileges
SHOW GRANTS ON TABLE IDENTIFIER($source_fqn);

SELECT
    CASE
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS has_ownership,
    'Current role must have OWNERSHIP on the table' AS assertion
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "privilege" = 'OWNERSHIP'
  AND "grantee_name" = CURRENT_ROLE();

-- Summary
SELECT
    $source_fqn                 AS table_tested,
    CURRENT_TIMESTAMP()         AS test_run_at,
    'Review PASS/FAIL results above. All must be PASS to proceed.' AS instruction;
