--------------------------------------------------------------------------------
-- 01_preflight_checks.sql
-- Phase 1: Confirm eligibility and discover the full dependency graph
--
-- Usage:
--   SET iceberg_db = 'MY_DATABASE';
--   SET iceberg_schema = 'MY_SCHEMA';
--   SET iceberg_table = 'MY_ICEBERG_TABLE';
--   Then run this script.
--------------------------------------------------------------------------------

-- ============================================================================
-- 1. TABLE ELIGIBILITY
-- ============================================================================

-- Confirm the table exists and is an Iceberg table
SELECT
    table_catalog       AS database_name,
    table_schema        AS schema_name,
    table_name,
    table_type,
    is_iceberg          AS is_iceberg,
    table_owner         AS owner_role,
    row_count,
    bytes,
    retention_time,
    created,
    last_altered
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE 1=0; -- placeholder; actual query below

SHOW TABLES LIKE $iceberg_table IN SCHEMA IDENTIFIER($iceberg_db || '.' || $iceberg_schema);

SELECT
    "name"              AS table_name,
    "kind"              AS table_kind,
    "is_iceberg"        AS is_iceberg,
    "owner"             AS owner_role,
    "rows"              AS row_count,
    "bytes"             AS bytes,
    "retention_time"    AS retention_days,
    "created_on"        AS created_on,
    "changed_on"        AS last_altered
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- Check current Iceberg version (must be 2 to upgrade)
-- NOTE: SHOW PARAMETERS is the documented method for version checking.
-- SYSTEM$GET_ICEBERG_TABLE_INFORMATION is for metadata generation, not version queries.
SHOW PARAMETERS LIKE 'ICEBERG_VERSION' IN TABLE IDENTIFIER($iceberg_db || '.' || $iceberg_schema || '.' || $iceberg_table);

SELECT
    "value"::INT AS current_iceberg_version,
    CASE
        WHEN "value"::INT = 2 THEN 'ELIGIBLE: Table is v2, can upgrade to v3'
        WHEN "value"::INT = 3 THEN 'ALREADY V3: No upgrade needed'
        ELSE 'UNKNOWN VERSION: Manual investigation required'
    END AS eligibility_status
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

-- ============================================================================
-- 2. DOWNSTREAM VIEWS
-- ============================================================================

-- NOTE: OBJECT_DEPENDENCIES is a view with up to 3-hour latency.
-- For freshly created objects, supplement with INFORMATION_SCHEMA.VIEWS.
SELECT
    referencing_object_name     AS view_name,
    referencing_object_domain   AS object_type,
    referencing_database        AS view_database,
    referencing_schema          AS view_schema
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE referenced_object_name = UPPER($iceberg_table)
  AND referenced_database     = UPPER($iceberg_db)
  AND referenced_schema       = UPPER($iceberg_schema)
  AND referencing_object_domain IN ('VIEW', 'MATERIALIZED VIEW')
ORDER BY view_database, view_schema, view_name;

-- Supplement: direct INFORMATION_SCHEMA check (no latency)
SELECT table_name AS view_name, view_definition
FROM IDENTIFIER($iceberg_db || '.INFORMATION_SCHEMA.VIEWS')
WHERE table_schema = UPPER($iceberg_schema)
  AND view_definition ILIKE '%' || $iceberg_table || '%';

-- ============================================================================
-- 3. STREAMS ON THE TABLE
-- ============================================================================

SHOW STREAMS IN SCHEMA IDENTIFIER($iceberg_db || '.' || $iceberg_schema);

SELECT
    "name"          AS stream_name,
    "table_name"    AS source_table,
    "type"          AS stream_type,
    "stale"         AS is_stale,
    "stale_after"   AS stale_after,
    "owner"         AS stream_owner,
    "mode"          AS stream_mode
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
WHERE "table_name" = $iceberg_db || '.' || $iceberg_schema || '.' || $iceberg_table;

-- ============================================================================
-- 4. DYNAMIC TABLES REFERENCING THIS TABLE
-- ============================================================================

SELECT
    referencing_object_name     AS dt_name,
    referencing_database        AS dt_database,
    referencing_schema          AS dt_schema
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE referenced_object_name = UPPER($iceberg_table)
  AND referenced_database     = UPPER($iceberg_db)
  AND referenced_schema       = UPPER($iceberg_schema)
  AND referencing_object_domain = 'DYNAMIC TABLE'
ORDER BY dt_database, dt_schema, dt_name;

-- Supplement: direct SHOW check (no latency)
SHOW DYNAMIC TABLES IN SCHEMA IDENTIFIER($iceberg_db || '.' || $iceberg_schema);

-- ============================================================================
-- 5. TASKS THAT REFERENCE THIS TABLE
-- ============================================================================

-- Check recent query history for task-based queries against this table
SELECT DISTINCT
    query_text,
    user_name,
    role_name,
    warehouse_name,
    execution_status,
    start_time
FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
WHERE query_type IN ('INSERT', 'MERGE', 'UPDATE', 'DELETE', 'CREATE_TABLE_AS_SELECT')
  AND CONTAINS(UPPER(query_text), UPPER($iceberg_table))
  AND start_time >= DATEADD('day', -7, CURRENT_TIMESTAMP())
  AND user_name LIKE '%_TASK%' OR role_name LIKE '%_TASK%'
ORDER BY start_time DESC
LIMIT 50;

-- ============================================================================
-- 6. ROW ACCESS POLICIES
-- ============================================================================

SELECT
    policy_name,
    policy_db       AS policy_database,
    policy_schema,
    ref_column_name AS protected_column,
    ref_database_name,
    ref_schema_name,
    ref_entity_name AS table_name
FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_NAME   => $iceberg_db || '.' || $iceberg_schema || '.' || $iceberg_table,
    REF_ENTITY_DOMAIN => 'TABLE'
))
WHERE policy_kind = 'ROW_ACCESS_POLICY';

-- ============================================================================
-- 7. MASKING POLICIES
-- ============================================================================

SELECT
    policy_name,
    policy_db       AS policy_database,
    policy_schema,
    ref_column_name AS masked_column,
    ref_database_name,
    ref_schema_name,
    ref_entity_name AS table_name
FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.POLICY_REFERENCES(
    REF_ENTITY_NAME   => $iceberg_db || '.' || $iceberg_schema || '.' || $iceberg_table,
    REF_ENTITY_DOMAIN => 'TABLE'
))
WHERE policy_kind = 'MASKING_POLICY';

-- ============================================================================
-- 8. GRANTS ON THE TABLE
-- ============================================================================

SHOW GRANTS ON TABLE IDENTIFIER($iceberg_db || '.' || $iceberg_schema || '.' || $iceberg_table);

SELECT
    "privilege"     AS privilege,
    "granted_on"    AS granted_on,
    "grantee_name"  AS grantee_role,
    "grant_option"  AS with_grant_option,
    "granted_by"    AS granted_by
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
ORDER BY "privilege", "grantee_name";

-- ============================================================================
-- 9. ALL OBJECT DEPENDENCIES (FULL GRAPH)
-- ============================================================================

SELECT
    referencing_object_name     AS dependent_object,
    referencing_object_domain   AS dependent_type,
    referencing_database,
    referencing_schema
FROM SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES
WHERE referenced_object_name = UPPER($iceberg_table)
  AND referenced_database     = UPPER($iceberg_db)
  AND referenced_schema       = UPPER($iceberg_schema)
ORDER BY referencing_object_domain, referencing_database, referencing_schema, referencing_object_name;

-- ============================================================================
-- 10. SUMMARY
-- ============================================================================

-- This final query summarizes the pre-flight findings for the go/no-go decision.
-- Review each section above for details before proceeding.

SELECT
    $iceberg_db || '.' || $iceberg_schema || '.' || $iceberg_table AS target_table,
    CURRENT_TIMESTAMP()                                             AS preflight_timestamp,
    CURRENT_ROLE()                                                  AS executing_role,
    'Review all sections above before proceeding to Phase 2'        AS next_step;
