--------------------------------------------------------------------------------
-- 02_clone_and_baseline.sql
-- Phase 2: Create a zero-copy clone and capture baseline metrics
--
-- Usage:
--   SET iceberg_db = 'MY_DATABASE';
--   SET iceberg_schema = 'MY_SCHEMA';
--   SET iceberg_table = 'MY_ICEBERG_TABLE';
--   Then run this script.
--
-- This script creates:
--   - A clone named <table>_V3_UPGRADE_CLONE
--   - Baseline metrics in temporary tables for comparison
--------------------------------------------------------------------------------

-- ============================================================================
-- 1. DEFINE CLONE NAME
-- ============================================================================

SET clone_table = $iceberg_table || '_V3_UPGRADE_CLONE';
SET clone_fqn   = $iceberg_db || '.' || $iceberg_schema || '.' || $clone_table;
SET source_fqn  = $iceberg_db || '.' || $iceberg_schema || '.' || $iceberg_table;

-- ============================================================================
-- 2. VERIFY NO ACTIVE DML LOCKS
-- ============================================================================

-- Check for active transactions on the source table
SELECT
    query_id,
    query_text,
    user_name,
    role_name,
    execution_status,
    start_time,
    DATEDIFF('second', start_time, CURRENT_TIMESTAMP()) AS running_seconds
FROM TABLE(INFORMATION_SCHEMA.QUERY_HISTORY_BY_WAREHOUSE())
WHERE execution_status = 'RUNNING'
  AND query_type IN ('INSERT', 'MERGE', 'UPDATE', 'DELETE', 'COPY')
  AND CONTAINS(UPPER(query_text), UPPER($iceberg_table))
ORDER BY start_time;

-- ============================================================================
-- 3. CREATE ZERO-COPY CLONE
-- ============================================================================

CREATE OR REPLACE ICEBERG TABLE IDENTIFIER($clone_fqn)
    CLONE IDENTIFIER($source_fqn);

-- Confirm clone was created
SHOW TABLES LIKE $clone_table IN SCHEMA IDENTIFIER($iceberg_db || '.' || $iceberg_schema);

SELECT
    "name"          AS table_name,
    "is_iceberg"    AS is_iceberg,
    "rows"          AS row_count,
    "bytes"         AS bytes,
    "created_on"    AS clone_created_at
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- ============================================================================
-- 4. CAPTURE BASELINE: ROW COUNT
-- ============================================================================

-- Source table row count
SELECT
    'SOURCE'        AS table_role,
    $source_fqn     AS table_name,
    COUNT(*)        AS row_count,
    CURRENT_TIMESTAMP() AS captured_at
FROM IDENTIFIER($source_fqn);

-- Clone row count (should match)
SELECT
    'CLONE'         AS table_role,
    $clone_fqn      AS table_name,
    COUNT(*)        AS row_count,
    CURRENT_TIMESTAMP() AS captured_at
FROM IDENTIFIER($clone_fqn);

-- ============================================================================
-- 5. CAPTURE BASELINE: ICEBERG VERSION
-- ============================================================================

SELECT
    'SOURCE' AS table_role,
    SYSTEM$GET_ICEBERG_TABLE_INFORMATION($source_fqn)::VARIANT:iceberg_version::INT AS iceberg_version;

SELECT
    'CLONE' AS table_role,
    SYSTEM$GET_ICEBERG_TABLE_INFORMATION($clone_fqn)::VARIANT:iceberg_version::INT AS iceberg_version;

-- ============================================================================
-- 6. CAPTURE BASELINE: DATA FINGERPRINT
-- ============================================================================

-- Hash-based fingerprint of all rows for integrity comparison.
-- Adjust the column list to match your table's key and measure columns.
-- Using HASH_AGG for a table-level checksum.
--
-- NOTE: Replace '*' with specific columns if the table has non-deterministic
--       columns (e.g., CURRENT_TIMESTAMP defaults).

SELECT
    'SOURCE'                AS table_role,
    HASH_AGG(*)             AS data_fingerprint,
    CURRENT_TIMESTAMP()     AS captured_at
FROM IDENTIFIER($source_fqn);

SELECT
    'CLONE'                 AS table_role,
    HASH_AGG(*)             AS data_fingerprint,
    CURRENT_TIMESTAMP()     AS captured_at
FROM IDENTIFIER($clone_fqn);

-- ============================================================================
-- 7. CAPTURE BASELINE: CRITICAL QUERY FINGERPRINTS
-- ============================================================================

-- Run your most important business queries and record their result hashes.
-- Below is a template. Replace with actual critical queries.
--
-- Example:
--
-- SELECT
--     'QUERY_1: Daily Revenue' AS query_label,
--     HASH_AGG(*) AS result_fingerprint
-- FROM (
--     SELECT date, SUM(revenue) AS total_revenue
--     FROM IDENTIFIER($source_fqn)
--     GROUP BY date
--     ORDER BY date
-- );
--
-- Repeat for each critical business query.

SELECT
    $source_fqn                     AS table_name,
    $clone_fqn                      AS clone_name,
    CURRENT_TIMESTAMP()             AS baseline_captured_at,
    'Baseline capture complete. Proceed to Phase 3 (validation on clone).' AS next_step;
