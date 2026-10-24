--------------------------------------------------------------------------------
-- 05_post_upgrade_validation.sql
-- Phase 5: Verify production table and all downstream objects are healthy
--
-- Prerequisites:
--   - Session variables set: iceberg_db, iceberg_schema, iceberg_table
--   - Phase 4 completed: table is now v3
--------------------------------------------------------------------------------

SET source_fqn = $iceberg_db || '.' || $iceberg_schema || '.' || $iceberg_table;

-- ============================================================================
-- 1. VERSION CONFIRMATION
-- ============================================================================

SHOW PARAMETERS LIKE 'ICEBERG_VERSION' IN TABLE IDENTIFIER($source_fqn);

SELECT
    $source_fqn AS table_name,
    "value"::INT AS iceberg_version,
    CASE
        WHEN "value"::INT = 3 THEN 'PASS'
        ELSE 'FAIL'
    END AS version_check
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- ============================================================================
-- 2. ROW COUNT INTEGRITY
-- ============================================================================

-- Compare against the baseline captured in Phase 2.
SELECT
    'POST_UPGRADE'      AS check_phase,
    COUNT(*)            AS row_count,
    CURRENT_TIMESTAMP() AS checked_at
FROM IDENTIFIER($source_fqn);

-- ============================================================================
-- 3. DATA FINGERPRINT
-- ============================================================================

SELECT
    'POST_UPGRADE'      AS check_phase,
    HASH_AGG(*)         AS data_fingerprint,
    CURRENT_TIMESTAMP() AS checked_at
FROM IDENTIFIER($source_fqn);

-- ============================================================================
-- 4. GRANT INTEGRITY
-- ============================================================================

-- Verify grants are unchanged from pre-flight (Phase 1).
SHOW GRANTS ON TABLE IDENTIFIER($source_fqn);

SELECT
    "privilege"     AS privilege,
    "grantee_name"  AS grantee_role,
    "grant_option"  AS with_grant_option,
    "granted_by"    AS granted_by
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "privilege", "grantee_name";

-- ============================================================================
-- 5. DOWNSTREAM VIEW HEALTH
-- ============================================================================

-- Query each dependent view to confirm no errors.
-- This must be customized per table. Template:
--
-- SELECT COUNT(*) AS row_count FROM <db>.<schema>.<dependent_view_1>;
-- SELECT COUNT(*) AS row_count FROM <db>.<schema>.<dependent_view_2>;
--
-- PASS: queries succeed and return expected counts.
-- FAIL: query error or unexpected count.

SELECT
    'VIEW_HEALTH_CHECK' AS check_name,
    'Add SELECT COUNT(*) queries for each dependent view from Phase 1 output' AS instruction;

-- ============================================================================
-- 6. STREAM HEALTH
-- ============================================================================

SHOW STREAMS IN SCHEMA IDENTIFIER($iceberg_db || '.' || $iceberg_schema);

SELECT
    "name"          AS stream_name,
    "table_name"    AS source_table,
    "stale"         AS is_stale,
    "stale_after"   AS stale_after,
    CASE
        WHEN "stale" = 'true' THEN 'WARNING: Stream is stale after upgrade'
        ELSE 'OK'
    END AS stream_status
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "table_name" = $source_fqn;

-- ============================================================================
-- 7. DYNAMIC TABLE REFRESH STATUS
-- ============================================================================

-- Check if any DTs referencing this table have entered an error state
-- or triggered an unexpected full refresh.

SELECT
    name                    AS dt_name,
    database_name,
    schema_name,
    refresh_mode,
    refresh_mode_reason,
    scheduling_state,
    last_completed_refresh_state,
    last_completed_refresh_state_message,
    data_timestamp
FROM SNOWFLAKE.ACCOUNT_USAGE.DYNAMIC_TABLES
WHERE scheduling_state IS NOT NULL
ORDER BY database_name, schema_name, name;

-- Filter for DTs that reference the upgraded table:
-- Cross-reference with Phase 1 dependency output.

-- ============================================================================
-- 8. TASK EXECUTION CHECK
-- ============================================================================

-- Look for task failures since the upgrade.
SELECT
    name                AS task_name,
    database_name,
    schema_name,
    state               AS task_state,
    error_code,
    error_message,
    completed_time
FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
WHERE completed_time >= DATEADD('hour', -2, CURRENT_TIMESTAMP())
  AND state = 'FAILED'
ORDER BY completed_time DESC
LIMIT 20;

-- ============================================================================
-- 9. POLICY ENFORCEMENT
-- ============================================================================

-- Verify policies are still attached.
SELECT
    policy_name,
    policy_kind,
    ref_column_name AS protected_column
FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_NAME   => $source_fqn,
    REF_ENTITY_DOMAIN => 'TABLE'
))
ORDER BY policy_kind, policy_name;

-- ============================================================================
-- 10. CRITICAL QUERY VALIDATION
-- ============================================================================

-- Re-run the same critical business queries from Phase 2/3.
-- Compare result fingerprints to baseline.
--
-- Template:
-- SELECT 'QUERY_1' AS label, HASH_AGG(*) AS fingerprint
-- FROM ( <your critical query using IDENTIFIER($source_fqn)> );

SELECT
    'CRITICAL_QUERY_VALIDATION' AS check_name,
    'Re-run critical queries and compare fingerprints to Phase 2 baseline' AS instruction;

-- ============================================================================
-- 11. VALIDATION SUMMARY
-- ============================================================================

SELECT
    $source_fqn                 AS validated_table,
    CURRENT_TIMESTAMP()         AS validation_timestamp,
    'Review all checks above.' AS instruction,
    'If ALL pass: enter monitoring period (24-72h). See docs/runbook.md.' AS on_pass,
    'If ANY fail: execute 06_rollback.sql immediately.' AS on_fail;
