# Architecture Decision Record: Clone-Validate-Upgrade Pattern

**Status:** Accepted
**Date:** 2026-10-18
**Decision makers:** Platform engineering team

## Context

Snowflake supports in-place upgrades of Iceberg tables from format version 2 to version 3 via `ALTER ICEBERG TABLE ... UPGRADE TO ICEBERG VERSION 3`. The upgrade is permanent and irreversible at the metadata level. Time Travel is the only restore mechanism.

A table in production is not a standalone artifact. It is a dependency boundary connected to views, streams, tasks, dynamic tables, row access policies, masking policies, grants, and external query engines. A format version change alters the metadata contract the table speaks to all of these consumers.

## Decision

All Iceberg v2→v3 upgrades follow a mandatory **clone → validate → upgrade → verify** pipeline with explicit go/no-go gates between phases.

### Phase model

```
Phase 1: Pre-flight     → Discover eligibility and full dependency graph
Phase 2: Clone          → Zero-copy clone + baseline metrics capture
Phase 3: Validate       → Upgrade clone, run workload validation
Phase 4: Upgrade        → Production ALTER in maintenance window
Phase 5: Verify         → Post-upgrade health checks
Phase 6: Rollback       → Time Travel restore (conditional)
```

### Go/no-go gates

| Gate | Condition to proceed |
|------|---------------------|
| Pre-flight → Clone | Table is eligible; all dependencies documented; approval ticket signed |
| Clone → Validate | Clone created; baseline metrics captured; no active DML locks |
| Validate → Upgrade | All validation queries pass on clone; stream behavior confirmed; DT refresh behavior confirmed |
| Upgrade → Verify | ALTER succeeded; version reads as 3 |
| Verify → Close | All post-upgrade checks pass; downstream objects healthy; monitoring period complete |

## Alternatives Considered

### 1. Direct upgrade without clone validation

**Rejected.** The upgrade is permanent. Without rehearsal, downstream failures (stream behavior changes, dynamic table reinitializations, external engine incompatibility) surface in production with no safe recovery path except Time Travel.

### 2. Blue-green table strategy (create new v3 table, migrate data, swap references)

**Rejected for most cases.** This approach provides stronger isolation but requires rewriting all downstream references, migrating data, and coordinating a cutover. The cost is disproportionate when the in-place upgrade preserves grants and object references. Reserved for tables with complex external engine dependencies where clone validation is insufficient.

### 3. Upgrade and monitor (reactive approach)

**Rejected.** Monitoring catches failures after they impact production. The clone-based approach catches them before production is touched. The cost of a zero-copy clone is negligible compared to the cost of a production incident.

## Consequences

### Positive
- Every upgrade is rehearsed before production is touched
- Dependency graph is explicitly documented, not assumed
- Rollback path is validated before the upgrade proceeds
- Operational knowledge is captured in queryable output, not tribal knowledge

### Negative
- Adds 1-2 hours of validation work per table upgrade
- Requires warehouse compute for validation queries on the clone
- Clone consumes storage only for data modified after clone creation (zero-copy)
- Maintenance window coordination is required

### Risks
- Time Travel retention may be insufficient if the monitoring period exceeds the retention window
- External engine compatibility cannot be fully tested via Snowflake-internal validation alone
- Default value semantics may behave differently in v3 for Snowflake-specific expressions

## Compliance

This pattern satisfies change management requirements for:
- SOC 2 Type II (change control, testing before production deployment)
- ISO 27001 (A.14.2.2 system change control procedures)
- Internal platform governance (approval before schema-level changes)
