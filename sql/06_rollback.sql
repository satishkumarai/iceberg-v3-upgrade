--------------------------------------------------------------------------------
-- 06_rollback.sql
-- Phase 6: Restore the pre-upgrade table state via Time Travel
--
-- Prerequisites:
--   - Session variables set: iceberg_db, iceberg_schema, iceberg_table
--   - pre_upgrade_ts variable set (from Phase 4 output)
--   - Time Travel retention window has not expired
--
-- WARNING: This restores the table to its pre-upgrade state.
--          Any data written AFTER the upgrade will be LOST.
--------------------------------------------------------------------------------

SET source_fqn = $iceberg_db || '.' || $iceberg_schema || '.' || $iceberg_table;

-- ============================================================================
-- 1. VERIFY ROLLBACK IS POSSIBLE
-- ============================================================================

-- Check current version (should be 3 if rolling back from upgrade)
SELECT
    $source_fqn AS table_name,
    SYSTEM$GET_ICEBERG_TABLE_INFORMATION($source_fqn)::VARIANT:iceberg_version::INT AS current_version;

-- Verify Time Travel retention
SHOW TABLES LIKE $iceberg_table IN SCHEMA IDENTIFIER($iceberg_db || '.' || $iceberg_schema);

SELECT
    "name"              AS table_name,
    "retention_time"    AS retention_days,
    "created_on"        AS created_at
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Verify the pre-upgrade timestamp is within the retention window
SELECT
    $pre_upgrade_ts::TIMESTAMP_TZ                           AS rollback_target,
    CURRENT_TIMESTAMP()                                     AS current_time,
    DATEDIFF('hour', $pre_upgrade_ts::TIMESTAMP_TZ, CURRENT_TIMESTAMP()) AS hours_since_upgrade,
    CASE
        WHEN hours_since_upgrade < 24 THEN 'WITHIN WINDOW: Rollback possible'
        ELSE 'WARNING: Check retention_time. Rollback may not be possible.'
    END AS rollback_feasibility;

-- ============================================================================
-- 2. CAPTURE CURRENT STATE BEFORE ROLLBACK
-- ============================================================================

-- Record current row count (data written after upgrade will be lost)
SELECT
    'PRE_ROLLBACK'      AS phase,
    COUNT(*)            AS current_row_count,
    CURRENT_TIMESTAMP() AS captured_at
FROM IDENTIFIER($source_fqn);

-- ============================================================================
-- 3. EXECUTE ROLLBACK VIA TIME TRAVEL CLONE
-- ============================================================================

-- This creates a new table from the Time Travel state at the pre-upgrade timestamp.
-- Using COPY GRANTS preserves all privileges except OWNERSHIP.
-- Using COPY TAGS preserves all tags.

-- First, pause any workloads writing to the table.

-- Find the upgrade timestamp if not already set:
-- SELECT query_id, start_time
--   FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY())
--   WHERE query_text ILIKE '%ORDERS%UPGRADE TO ICEBERG VERSION 3%'
--   ORDER BY start_time DESC;

-- Save existing grants for reference
SHOW GRANTS ON TABLE IDENTIFIER($source_fqn);

SELECT
    "privilege"     AS privilege,
    "grantee_name"  AS grantee_role,
    "grant_option"  AS with_grant_option
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "privilege", "grantee_name";

-- Execute the rollback via Time Travel clone
-- NOTE: The clone points to a time BEFORE the upgrade, so it is a v2 table.
-- COPY GRANTS copies all privileges except OWNERSHIP.
SET rollback_table = $iceberg_db || '.' || $iceberg_schema || '.' || $iceberg_table || '_V2_RESTORED';

CREATE ICEBERG TABLE IDENTIFIER($rollback_table)
    CLONE IDENTIFIER($source_fqn)
    AT (TIMESTAMP => $pre_upgrade_ts::TIMESTAMP_LTZ)
    COPY GRANTS;

-- ============================================================================
-- 4. VERIFY ROLLBACK
-- ============================================================================

-- Confirm version is back to 2
SHOW PARAMETERS LIKE 'ICEBERG_VERSION' IN TABLE IDENTIFIER($rollback_table);

SELECT
    $rollback_table AS table_name,
    "value"::INT AS iceberg_version,
    CASE
        WHEN "value"::INT = 2 THEN 'PASS: Table restored to v2'
        ELSE 'FAIL: Version is not 2. Manual intervention required.'
    END AS rollback_status
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Confirm row count matches pre-upgrade baseline
SELECT
    'POST_ROLLBACK'     AS phase,
    COUNT(*)            AS row_count,
    CURRENT_TIMESTAMP() AS checked_at
FROM IDENTIFIER($source_fqn);

-- Confirm data fingerprint matches baseline
SELECT
    'POST_ROLLBACK'     AS phase,
    HASH_AGG(*)         AS data_fingerprint,
    CURRENT_TIMESTAMP() AS checked_at
FROM IDENTIFIER($source_fqn);

-- ============================================================================
-- 5. RE-APPLY GRANTS
-- ============================================================================

-- Grants from CREATE OR REPLACE ... CLONE may not fully preserve.
-- Re-apply from the grant output captured in Step 3 above.
--
-- Template:
-- GRANT SELECT ON TABLE IDENTIFIER($source_fqn) TO ROLE <role_name>;
-- GRANT INSERT ON TABLE IDENTIFIER($source_fqn) TO ROLE <role_name>;
--
-- Repeat for each grant from the pre-rollback output.

SELECT
    'GRANT_RESTORATION' AS check_name,
    'Re-apply grants from Step 3 output. Verify with SHOW GRANTS.' AS instruction;

-- ============================================================================
-- 6. RECREATE STREAMS (IF APPLICABLE)
-- ============================================================================

-- Streams on the original table become invalid after CREATE OR REPLACE.
-- Recreate them from the Phase 1 pre-flight output.
--
-- Template:
-- CREATE OR REPLACE STREAM <stream_name> ON TABLE IDENTIFIER($source_fqn);

SELECT
    'STREAM_RECREATION' AS check_name,
    'Recreate streams from Phase 1 output. Verify with SHOW STREAMS.' AS instruction;

-- ============================================================================
-- 7. ROLLBACK SUMMARY
-- ============================================================================

SELECT
    $source_fqn                 AS rolled_back_table,
    $pre_upgrade_ts             AS restored_to_timestamp,
    CURRENT_TIMESTAMP()         AS rollback_completed_at,
    CURRENT_ROLE()              AS executing_role,
    'Verify grants, streams, and downstream objects.' AS next_step,
    'Document root cause in the upgrade ticket.' AS follow_up;
