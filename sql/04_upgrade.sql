--------------------------------------------------------------------------------
-- 04_upgrade.sql
-- Phase 4: Execute the production Iceberg v2 → v3 upgrade
--
-- Prerequisites:
--   - Session variables set: iceberg_db, iceberg_schema, iceberg_table
--   - Phases 1-3 completed and all validations pass
--   - Maintenance window active
--   - Upgrade ticket approved
--
-- IMPORTANT: This operation is PERMANENT. There is no downgrade path.
--            Rollback requires Time Travel (see 06_rollback.sql).
--------------------------------------------------------------------------------

SET source_fqn = $iceberg_db || '.' || $iceberg_schema || '.' || $iceberg_table;

-- ============================================================================
-- 1. PRE-UPGRADE GUARDS
-- ============================================================================

-- Confirm current version is 2 (guard against double-execution)
SHOW PARAMETERS LIKE 'ICEBERG_VERSION' IN TABLE IDENTIFIER($source_fqn);

SELECT
    "value"::INT AS current_version,
    CASE
        WHEN "value"::INT = 2 THEN 'READY: Table is v2. Safe to proceed.'
        WHEN "value"::INT = 3 THEN 'ABORT: Table is already v3. No action needed.'
        ELSE 'ABORT: Unexpected version. Investigate before proceeding.'
    END AS guard_status
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Confirm no active DML
SELECT
    query_id,
    query_text,
    user_name,
    execution_status,
    start_time
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_WAREHOUSE())
WHERE execution_status = 'RUNNING'
  AND query_type IN ('INSERT', 'MERGE', 'UPDATE', 'DELETE', 'COPY')
  AND CONTAINS(UPPER(query_text), UPPER($iceberg_table))
ORDER BY start_time;

-- Confirm Time Travel retention is adequate for rollback
SHOW TABLES LIKE $iceberg_table IN SCHEMA IDENTIFIER($iceberg_db || '.' || $iceberg_schema);

SELECT
    "name"              AS table_name,
    "retention_time"    AS retention_days,
    CASE
        WHEN "retention_time"::INT >= 1 THEN 'OK: Retention sufficient for rollback'
        ELSE 'WARNING: Retention < 1 day. Rollback window may be insufficient.'
    END AS retention_status
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- ============================================================================
-- 2. RECORD PRE-UPGRADE TIMESTAMP
-- ============================================================================

-- Save this timestamp. It is the Time Travel reference point for rollback.
SET pre_upgrade_ts = CURRENT_TIMESTAMP()::STRING;

SELECT
    $pre_upgrade_ts AS pre_upgrade_timestamp,
    'SAVE THIS VALUE. Required for rollback via Time Travel.' AS instruction;

-- ============================================================================
-- 3. EXECUTE THE UPGRADE
-- ============================================================================

ALTER ICEBERG TABLE IDENTIFIER($source_fqn) UPGRADE TO ICEBERG VERSION 3;

-- ============================================================================
-- 4. POST-UPGRADE IMMEDIATE VERIFICATION
-- ============================================================================

-- Confirm version is now 3
SHOW PARAMETERS LIKE 'ICEBERG_VERSION' IN TABLE IDENTIFIER($source_fqn);

SELECT
    $source_fqn AS table_name,
    "value"::INT AS iceberg_version,
    CASE
        WHEN "value"::INT = 3 THEN 'PASS: Upgrade successful. Table is v3.'
        ELSE 'FAIL: Version is not 3. Investigate immediately.'
    END AS upgrade_status
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Confirm table is queryable
SELECT COUNT(*) AS post_upgrade_row_count FROM IDENTIFIER($source_fqn);

-- ============================================================================
-- 5. UPGRADE RECORD
-- ============================================================================

SELECT
    $source_fqn                 AS upgraded_table,
    $pre_upgrade_ts             AS rollback_timestamp,
    CURRENT_TIMESTAMP()         AS upgrade_completed_at,
    CURRENT_ROLE()              AS executing_role,
    CURRENT_WAREHOUSE()         AS executing_warehouse,
    'Proceed to Phase 5 (post-upgrade validation).' AS next_step,
    'If any issue found, execute 06_rollback.sql using the rollback_timestamp above.' AS rollback_instruction;
