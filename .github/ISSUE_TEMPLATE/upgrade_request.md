---
name: Iceberg v3 Upgrade Request
about: Request an Iceberg table upgrade from v2 to v3
title: "[UPGRADE] <database>.<schema>.<table> — Iceberg v2 → v3"
labels: iceberg-upgrade, change-request
assignees: ''
---

## Table Information

| Field | Value |
|-------|-------|
| **Database** | |
| **Schema** | |
| **Table** | |
| **Current Iceberg Version** | 2 |
| **Table Owner** | |
| **Approximate Row Count** | |
| **Time Travel Retention (days)** | |

## Business Justification

Why is this upgrade needed? What v3 features will be used?

## Dependency Assessment

### Pre-flight completed?
- [ ] `01_preflight_checks.sql` executed
- [ ] Dependency report attached

### Known downstream dependencies
| Object | Type | Owner | Impact Assessment |
|--------|------|-------|-------------------|
| | VIEW | | |
| | STREAM | | |
| | DYNAMIC TABLE | | |
| | TASK | | |

### External consumers
- [ ] No external engines read this table
- [ ] External engines identified: (list them)

### Policies
- [ ] No row access or masking policies
- [ ] Policies identified: (list them)

## Validation Plan

- [ ] Clone-based validation completed (`03_validate_clone.sql`)
- [ ] Critical business queries tested on clone
- [ ] Stream behavior validated
- [ ] Dynamic table refresh validated
- [ ] Default value behavior validated
- [ ] DML operations validated
- [ ] Policy enforcement validated

## Upgrade Window

| Field | Value |
|-------|-------|
| **Proposed date/time** | |
| **Maintenance window duration** | |
| **DML pause start** | |
| **DML pause end** | |
| **Rollback deadline** | |

## Rollback Plan

- [ ] Time Travel retention verified (>= 1 day)
- [ ] `pre_upgrade_ts` will be recorded during upgrade
- [ ] Rollback procedure: `06_rollback.sql`
- [ ] Rollback owner: (name)

## Approvals

- [ ] Table owner
- [ ] Platform engineering lead
- [ ] Downstream pipeline owners notified
- [ ] External consumer teams notified (if applicable)
