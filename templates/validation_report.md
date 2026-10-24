# Post-Upgrade Validation Report

## Summary

| Field | Value |
|-------|-------|
| Table | `<database>.<schema>.<table>` |
| Upgrade date | |
| Validated by | |
| Report date | |
| Overall status | PASS / FAIL |

## Version Confirmation

| Check | Expected | Actual | Status |
|-------|----------|--------|--------|
| Iceberg version | 3 | | |

## Data Integrity

| Check | Baseline (Phase 2) | Post-Upgrade | Status |
|-------|---------------------|--------------|--------|
| Row count | | | |
| Data fingerprint (HASH_AGG) | | | |

## Critical Query Validation

| Query Label | Baseline Fingerprint | Post-Upgrade Fingerprint | Status |
|-------------|---------------------|--------------------------|--------|
| Query 1: | | | |
| Query 2: | | | |
| Query 3: | | | |

## Downstream Object Health

### Views
| View Name | Query Status | Row Count | Status |
|-----------|-------------|-----------|--------|
| | | | |

### Streams
| Stream Name | Stale? | Mode | Status |
|-------------|--------|------|--------|
| | | | |

### Dynamic Tables
| DT Name | Refresh State | Last Refresh | Status |
|---------|---------------|-------------|--------|
| | | | |

### Tasks
| Task Name | Last Run | State | Status |
|-----------|----------|-------|--------|
| | | | |

## Security

### Grants
| Privilege | Grantee | Pre-Upgrade | Post-Upgrade | Status |
|-----------|---------|-------------|-------------|--------|
| | | | | |

### Policies
| Policy | Kind | Column | Enforcing? | Status |
|--------|------|--------|-----------|--------|
| | | | | |

## External Consumers

| Engine / System | Read Test | Write Test | Status |
|-----------------|-----------|-----------|--------|
| | | | |

## Monitoring Period

| Signal | Check Method | Status |
|--------|-------------|--------|
| Query failures | QUERY_HISTORY | |
| Stream lag | SHOW STREAMS | |
| DT refresh failures | DYNAMIC_TABLE_REFRESH_HISTORY | |
| Task failures | TASK_HISTORY | |

## Sign-Off

| Role | Name | Signed Off | Date |
|------|------|-----------|------|
| Upgrade operator | | [ ] | |
| Table owner | | [ ] | |
| Platform lead | | [ ] | |

## Notes

(Additional observations, warnings, or follow-up items.)
