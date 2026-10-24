# Rollback Plan: Iceberg v3 Upgrade

## Overview

The Iceberg v2→v3 upgrade is **permanent at the metadata level**. There is no `ALTER ICEBERG TABLE ... DOWNGRADE TO ICEBERG VERSION 2`. The rollback strategy relies on **Time Travel** to restore the table to its pre-upgrade state.

## Decision Tree

```
Upgrade completed
    │
    ├── Post-upgrade validation passes?
    │   ├── YES → Enter monitoring period (24-72h)
    │   │         │
    │   │         ├── Monitoring period clean?
    │   │         │   ├── YES → Close upgrade ticket. Done.
    │   │         │   └── NO  → Evaluate failure severity
    │   │         │             │
    │   │         │             ├── Data correctness issue? → ROLLBACK
    │   │         │             ├── Stream broken?          → ROLLBACK
    │   │         │             ├── External engine broken?  → ROLLBACK or MITIGATE
    │   │         │             └── Performance regression?  → INVESTIGATE, then decide
    │   │         │
    │   └── NO  → Immediate ROLLBACK
    │
    └── Upgrade failed (ALTER errored)?
        └── Table remains v2. No rollback needed. Investigate error.
```

## Rollback Procedure

### Step 1: Verify Time Travel availability

```sql
SHOW TABLES LIKE '<table_name>' IN SCHEMA <db>.<schema>;
-- Check RETENTION_TIME column — must be > 0
-- Check that the pre-upgrade timestamp is within the retention window
```

### Step 2: Record the pre-upgrade timestamp

This timestamp was captured in Phase 4 (`04_upgrade.sql`) before the ALTER was executed. Retrieve it from the upgrade log or the session variable.

### Step 3: Restore via Time Travel

**Option A: CREATE OR REPLACE from Time Travel**

```sql
CREATE OR REPLACE ICEBERG TABLE <db>.<schema>.<table>
    CLONE <db>.<schema>.<table>
    AT (TIMESTAMP => '<pre_upgrade_timestamp>'::TIMESTAMP_TZ);
```

**Option B: UNDROP (if the table was dropped and recreated)**

```sql
-- Only applicable if the table was dropped
UNDROP TABLE <db>.<schema>.<table>;
```

### Step 4: Verify rollback

```sql
-- Confirm version is back to 2
SELECT SYSTEM$GET_ICEBERG_TABLE_INFORMATION('<db>.<schema>.<table>')::VARIANT:iceberg_version AS version;

-- Confirm row count matches baseline
SELECT COUNT(*) FROM <db>.<schema>.<table>;

-- Run critical business queries
```

### Step 5: Notify downstream consumers

After rollback, notify:
- Teams that depend on downstream views
- Pipeline owners (tasks, streams, dynamic tables)
- External engine operators
- The approval chain from the upgrade ticket

## Rollback Constraints

| Constraint | Impact |
|-----------|--------|
| Time Travel retention window | Rollback is only possible within the retention period. Default is 1 day; check table-level override. |
| Data written after upgrade | Any data written to the v3 table after the upgrade will be lost on rollback. Plan DML pauses accordingly. |
| Grants and policies | `CLONE ... AT` preserves grants from the cloned point in time. Verify grants after restore. |
| Streams | Streams on the original table may become stale after a CLONE-based restore. Recreate streams after rollback. |
| Dynamic tables | DTs referencing the table may need a manual refresh after rollback. Monitor refresh status. |

## When NOT to Rollback

- **Performance regression only:** If queries are slower but correct, investigate warehouse sizing and query patterns before reverting. v3 metadata changes may require query plan adaptation.
- **External engine incompatibility only:** If the external engine can be updated to support v3, that may be preferable to reverting. Coordinate with the engine team.
- **Cosmetic metadata differences:** v3 adds metadata fields. If downstream consumers warn about unknown fields but still function, this is not a rollback trigger.

## Post-Rollback Actions

1. Update the upgrade ticket with rollback details and root cause
2. Schedule a post-mortem within 48 hours
3. Document the specific failure that triggered rollback
4. Update the validation checklist to cover the failure scenario
5. Re-plan the upgrade with the additional validation step
