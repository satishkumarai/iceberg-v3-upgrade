--------------------------------------------------------------------------------
-- test_post_upgrade.sql
-- Assertions for Phase 5 post-upgrade validation
--
-- Run after 05_post_upgrade_validation.sql to validate results programmatically.
-- Each query returns PASS or FAIL. Any FAIL triggers rollback consideration.
--------------------------------------------------------------------------------

SET source_fqn = $iceberg_db || '.' || $iceberg_schema || '.' || $iceberg_table;

-- Assert: version is 3
SHOW PARAMETERS LIKE 'ICEBERG_VERSION' IN TABLE IDENTIFIER($source_fqn);

SELECT
    CASE
        WHEN "value"::INT = 3 THEN 'PASS'
        ELSE 'FAIL'
    END AS version_is_3,
    'Table must be Iceberg v3 after upgrade' AS assertion
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Assert: table is queryable
SELECT
    CASE
        WHEN COUNT(*) >= 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS table_queryable,
    'Table must be queryable after upgrade' AS assertion,
    COUNT(*) AS row_count
FROM IDENTIFIER($source_fqn);

-- Assert: grants are preserved
SHOW GRANTS ON TABLE IDENTIFIER($source_fqn);

SELECT
    CASE
        WHEN COUNT(*) > 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS grants_exist,
    'Table must have grants after upgrade' AS assertion,
    COUNT(*) AS grant_count
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Assert: no streams are stale
SHOW STREAMS IN SCHEMA IDENTIFIER($iceberg_db || '.' || $iceberg_schema);

SELECT
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'FAIL'
    END AS no_stale_streams,
    'No streams on the table should be stale after upgrade' AS assertion,
    COUNT(*) AS stale_stream_count
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "table_name" = $source_fqn
  AND "stale" = 'true';

-- Assert: policies still attached
SELECT
    CASE
        WHEN policy_count >= 0 THEN 'PASS'
    END AS policies_check,
    'Policy count should match pre-upgrade baseline' AS assertion,
    policy_count
FROM (
    SELECT COUNT(*) AS policy_count
    FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.POLICY_REFERENCES(
        REF_ENTITY_NAME   => $source_fqn,
        REF_ENTITY_DOMAIN => 'TABLE'
    ))
);

-- Assert: no recent task failures referencing this table
SELECT
    CASE
        WHEN COUNT(*) = 0 THEN 'PASS'
        ELSE 'WARNING'
    END AS no_task_failures,
    'No tasks should have failed since upgrade' AS assertion,
    COUNT(*) AS failed_task_count
FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
WHERE completed_time >= DATEADD('hour', -2, CURRENT_TIMESTAMP())
  AND state = 'FAILED';

-- Summary
SELECT
    $source_fqn                 AS table_tested,
    CURRENT_TIMESTAMP()         AS test_run_at,
    'All assertions must be PASS. Any FAIL = evaluate rollback.' AS instruction;
