--------------------------------------------------------------------------------
-- 03_validate_clone.sql
-- Phase 3: Upgrade the clone to v3 and validate workload behavior
--
-- Prerequisites:
--   - Session variables set: iceberg_db, iceberg_schema, iceberg_table
--   - Phase 2 completed: clone exists and baseline metrics captured
--------------------------------------------------------------------------------

SET clone_table = $iceberg_table || '_V3_UPGRADE_CLONE';
SET clone_fqn   = $iceberg_db || '.' || $iceberg_schema || '.' || $clone_table;
SET source_fqn  = $iceberg_db || '.' || $iceberg_schema || '.' || $iceberg_table;

-- ============================================================================
-- 1. UPGRADE THE CLONE TO V3
-- ============================================================================

ALTER ICEBERG TABLE IDENTIFIER($clone_fqn) UPGRADE TO ICEBERG VERSION 3;

-- Confirm version
SHOW PARAMETERS LIKE 'ICEBERG_VERSION' IN TABLE IDENTIFIER($clone_fqn);

SELECT
    $clone_fqn AS table_name,
    "value"::INT AS iceberg_version,
    CASE
        WHEN "value"::INT = 3 THEN 'PASS: Clone is now v3'
        ELSE 'FAIL: Clone did not upgrade to v3'
    END AS status
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- ============================================================================
-- 2. DATA INTEGRITY CHECK
-- ============================================================================

-- Row count comparison
SELECT
    'CLONE_POST_UPGRADE'    AS check_name,
    COUNT(*)                AS row_count,
    CURRENT_TIMESTAMP()     AS checked_at
FROM IDENTIFIER($clone_fqn);

-- Data fingerprint comparison
-- This should match the baseline from Phase 2.
SELECT
    'CLONE_POST_UPGRADE'    AS check_name,
    HASH_AGG(*)             AS data_fingerprint,
    CURRENT_TIMESTAMP()     AS checked_at
FROM IDENTIFIER($clone_fqn);

-- ============================================================================
-- 3. QUERY CORRECTNESS
-- ============================================================================

-- Run critical business queries against the clone.
-- Compare results to the baseline fingerprints captured in Phase 2.
--
-- Template:
--
-- SELECT
--     'QUERY_1: Daily Revenue' AS query_label,
--     HASH_AGG(*) AS result_fingerprint
-- FROM (
--     SELECT date, SUM(revenue) AS total_revenue
--     FROM IDENTIFIER($clone_fqn)
--     GROUP BY date
--     ORDER BY date
-- );
--
-- PASS: result_fingerprint matches Phase 2 baseline.
-- FAIL: result_fingerprint differs — investigate before proceeding.

-- ============================================================================
-- 4. STREAM BEHAVIOR VALIDATION
-- ============================================================================

-- Create a test stream on the clone to verify change tracking still works.

SET test_stream = $iceberg_db || '.' || $iceberg_schema || '.' || $clone_table || '_TEST_STREAM';

-- NOTE: Stream creation on Iceberg tables requires CHANGE_TRACKING = TRUE.
-- If this fails, the source table may not have change tracking enabled.
-- This is an important compatibility check.

-- CREATE OR REPLACE STREAM IDENTIFIER($test_stream) ON TABLE IDENTIFIER($clone_fqn)
--     SHOW_INITIAL_ROWS = FALSE;

-- Insert test data to exercise the stream
-- INSERT INTO IDENTIFIER($clone_fqn) (col1, col2)
--     VALUES ('stream_test', CURRENT_TIMESTAMP());

-- Consume the stream
-- SELECT * FROM IDENTIFIER($test_stream);

-- Expected: the inserted row appears in the stream.
-- If the stream returns empty or errors, this is a v3 compatibility issue.

SELECT
    'STREAM_VALIDATION' AS check_name,
    'Uncomment and customize stream tests above for your table schema' AS instruction;

-- ============================================================================
-- 5. DEFAULT VALUE BEHAVIOR
-- ============================================================================

-- v3 may handle default values differently, especially for Snowflake-specific
-- expressions. Test by inserting rows that rely on DEFAULT.

-- INSERT INTO IDENTIFIER($clone_fqn) (required_col)
--     VALUES ('default_test');
--
-- SELECT * FROM IDENTIFIER($clone_fqn) WHERE required_col = 'default_test';
--
-- Verify: default columns populated correctly.
-- Watch for: Snowflake-specific defaults that may not translate to v3 literals.

SELECT
    'DEFAULT_VALUE_VALIDATION' AS check_name,
    'Uncomment and customize default value tests above' AS instruction;

-- ============================================================================
-- 6. DML OPERATIONS
-- ============================================================================

-- Verify all DML operations work on the v3 clone.

-- INSERT test
-- INSERT INTO IDENTIFIER($clone_fqn) (col1) VALUES ('dml_insert_test');

-- UPDATE test
-- UPDATE IDENTIFIER($clone_fqn) SET col1 = 'dml_update_test' WHERE col1 = 'dml_insert_test';

-- DELETE test
-- DELETE FROM IDENTIFIER($clone_fqn) WHERE col1 = 'dml_update_test';

-- MERGE test
-- MERGE INTO IDENTIFIER($clone_fqn) t
--     USING (SELECT 'merge_test' AS col1) s ON t.col1 = s.col1
--     WHEN NOT MATCHED THEN INSERT (col1) VALUES (s.col1);

SELECT
    'DML_VALIDATION' AS check_name,
    'Uncomment and customize DML tests above for your table schema' AS instruction;

-- ============================================================================
-- 7. POLICY VALIDATION
-- ============================================================================

-- If the source table has row access or masking policies, verify they
-- still function correctly on the v3 clone.
--
-- Switch to a restricted role and query the clone:
-- USE ROLE <restricted_role>;
-- SELECT * FROM IDENTIFIER($clone_fqn) LIMIT 10;
--
-- Expected: policies enforce correctly (masked values, row filtering).
-- Fail: unmasked data visible or policy error.

SELECT
    'POLICY_VALIDATION' AS check_name,
    'Test with restricted roles if policies exist on the source table' AS instruction;

-- ============================================================================
-- 8. VALIDATION SUMMARY
-- ============================================================================

SELECT
    $clone_fqn                  AS validated_table,
    CURRENT_TIMESTAMP()         AS validation_timestamp,
    CURRENT_ROLE()              AS validating_role,
    'Review all checks above. If all PASS, proceed to Phase 4 (production upgrade).' AS next_step,
    'If any check fails, do NOT proceed. Document the failure and investigate.' AS warning;
