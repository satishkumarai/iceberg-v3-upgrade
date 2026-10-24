# Operator Runbook: Iceberg v2 → v3 Upgrade

## Scope

This runbook covers the end-to-end procedure for upgrading a single Snowflake-managed Iceberg table from format version 2 to version 3.

## Prerequisites

- [ ] Table is Snowflake-managed (not externally managed via Glue, Polaris, etc.)
- [ ] Role has OWNERSHIP on the table or equivalent privileges
- [ ] Time Travel retention is ≥ 1 day (confirm via `SHOW TABLES`)
- [ ] Maintenance window scheduled — no concurrent DML expected
- [ ] Upgrade ticket approved (see `templates/upgrade_ticket.md`)
- [ ] Dependency report generated (see Phase 1)

## Procedure

### Phase 1: Pre-flight Checks

**Script:** `sql/01_preflight_checks.sql`

**Purpose:** Confirm eligibility and discover the full dependency graph.

**Steps:**
1. Set session variables for the target table
2. Run the pre-flight script
3. Review output:
   - Table eligibility (is it Snowflake-managed Iceberg? is it v2?)
   - Downstream views
   - Streams on the table
   - Dynamic tables that reference it
   - Tasks that query it
   - Row access policies and masking policies
   - Grants and ownership
4. Save the dependency report output

**Go/no-go:** All dependencies documented. No unexpected consumers. Approval signed.

---

### Phase 2: Clone and Baseline

**Script:** `sql/02_clone_and_baseline.sql`

**Purpose:** Create a zero-copy clone and capture baseline metrics.

**Steps:**
1. Create clone: `CREATE ICEBERG TABLE ... CLONE ...`
2. Capture baseline row count
3. Capture baseline checksum (hash_agg on key columns)
4. Record current table version (should be 2)
5. Snapshot query fingerprints for critical business queries

**Go/no-go:** Clone created. Baseline metrics stored. No active DML locks on source.

---

### Phase 3: Validate on Clone

**Script:** `sql/03_validate_clone.sql`

**Purpose:** Upgrade the clone to v3 and validate the workload.

**Steps:**
1. Upgrade the clone: `ALTER ICEBERG TABLE ... UPGRADE TO ICEBERG VERSION 3`
2. Confirm clone version is 3
3. Run critical business queries against clone — compare results to baseline
4. Test stream behavior (if streams exist on the source):
   - Create a test stream on the clone
   - Insert test data
   - Consume the stream
   - Verify change tracking works
5. Test dynamic table refresh behavior (if DTs depend on the source):
   - Note: DTs cannot reference a clone directly; validate query patterns manually
6. Validate default value behavior:
   - Insert rows relying on DEFAULT
   - Confirm values match expectations
7. Validate policy enforcement:
   - Query with a restricted role
   - Confirm row access and masking policies function

**Go/no-go:** All validation queries pass. Stream behavior confirmed. No regressions.

---

### Phase 4: Upgrade Production

**Script:** `sql/04_upgrade.sql`

**Purpose:** Execute the production upgrade.

**Steps:**
1. Confirm maintenance window is active
2. Verify no active DML on the table
3. Record pre-upgrade timestamp (for Time Travel rollback reference)
4. Run the upgrade: `ALTER ICEBERG TABLE ... UPGRADE TO ICEBERG VERSION 3`
5. Confirm version is 3
6. Confirm table is queryable

**Go/no-go:** Version reads as 3. Table is queryable. No errors.

---

### Phase 5: Post-Upgrade Validation

**Script:** `sql/05_post_upgrade_validation.sql`

**Purpose:** Verify the production table and all downstream objects are healthy.

**Steps:**
1. Confirm version is 3
2. Confirm row count matches pre-upgrade baseline
3. Run critical business queries — compare to baseline fingerprints
4. Check downstream views (query each, confirm no errors)
5. Check streams (consume test data, confirm change tracking)
6. Check dynamic table refresh status
7. Check task execution history (confirm no failures)
8. Validate grants are intact
9. Validate policies are still attached

**Go/no-go:** All checks pass. Monitoring period begins.

---

### Phase 6: Rollback (if needed)

**Script:** `sql/06_rollback.sql`

**Purpose:** Restore the pre-upgrade table state via Time Travel.

**Trigger conditions:**
- Critical business query returns different results
- Stream behavior is broken
- Dynamic table entered unexpected full refresh
- External engine cannot read the table
- Policy enforcement changed behavior

**See:** `docs/rollback-plan.md` for the full decision tree.

---

## Monitoring Period

After Phase 5, monitor for **24-72 hours** depending on table criticality:

| Signal | Where to check |
|--------|---------------|
| Query failures | `SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY` filtered by table name |
| Stream lag | `SHOW STREAMS` — check `stale_after` |
| DT refresh failures | `SNOWFLAKE.ACCOUNT_USAGE.DYNAMIC_TABLE_REFRESH_HISTORY` |
| Task failures | `SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY` |
| Policy violations | Application-level audit logs |

## Cleanup

After the monitoring period passes without issues:

```sql
-- Drop the validation clone
DROP TABLE IF EXISTS <clone_table>;

-- Drop any test streams created during validation
DROP STREAM IF EXISTS <test_stream>;
```

## Escalation

If any phase fails and the root cause is unclear:
1. Do not proceed to the next phase
2. Document the failure in the upgrade ticket
3. Escalate to the platform engineering lead
4. If production is impacted, execute Phase 6 (rollback) immediately
