# Upgrade Ticket: Iceberg v2 → v3

## Table

| Field | Value |
|-------|-------|
| Database | |
| Schema | |
| Table | |
| Current Version | 2 |
| Target Version | 3 |

## Requester

| Field | Value |
|-------|-------|
| Requested by | |
| Date | |
| Business justification | |

## Pre-Upgrade Checklist

- [ ] Pre-flight checks completed (`01_preflight_checks.sql`)
- [ ] Dependency report generated and reviewed
- [ ] Clone created and baseline captured (`02_clone_and_baseline.sql`)
- [ ] Clone validation passed (`03_validate_clone.sql`)
- [ ] All downstream owners notified
- [ ] External consumers assessed
- [ ] Maintenance window scheduled
- [ ] DML pause coordinated
- [ ] Rollback plan reviewed (`docs/rollback-plan.md`)

## Approval Chain

| Role | Name | Approved | Date |
|------|------|----------|------|
| Table owner | | [ ] | |
| Platform lead | | [ ] | |
| Pipeline owner | | [ ] | |
| Security/governance | | [ ] | |

## Upgrade Execution

| Field | Value |
|-------|-------|
| Executed by | |
| Execution timestamp | |
| Pre-upgrade timestamp (for rollback) | |
| Warehouse used | |
| Role used | |

## Post-Upgrade Status

- [ ] Version confirmed as 3
- [ ] Row count matches baseline
- [ ] Data fingerprint matches baseline
- [ ] Grants intact
- [ ] Streams healthy
- [ ] Dynamic tables healthy
- [ ] Tasks executing normally
- [ ] Policies enforcing correctly
- [ ] Critical queries validated

## Monitoring Period

| Field | Value |
|-------|-------|
| Start | |
| End | |
| Monitoring owner | |
| Issues found | None / (describe) |

## Final Status

- [ ] **COMPLETE** — Monitoring period passed. No issues. Upgrade closed.
- [ ] **ROLLED BACK** — Issue found. Rollback executed. Root cause documented below.

### Root Cause (if rolled back)

(Describe the failure, the rollback execution, and lessons learned.)
