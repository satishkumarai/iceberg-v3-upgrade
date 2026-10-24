# Iceberg v2 → v3 Upgrade Toolkit

Production-grade framework for upgrading Snowflake-managed Iceberg tables from format version 2 to version 3. Built from real production lessons: the ALTER statement is one line; the dependency validation is the actual project.

## Why this exists

An Iceberg table in Snowflake is never just a table. It carries grants, policies, views, streams, dynamic tables, and downstream assumptions that only become visible when the metadata changes underneath them. This toolkit codifies the operational discipline that prevents a one-line DDL from becoming a production incident.

## Architecture

The upgrade follows a **clone → validate → upgrade → verify** pipeline with explicit go/no-go gates between phases.

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│  Pre-flight  │───▶│   Clone &   │───▶│  Validate   │───▶│   Upgrade   │───▶│ Post-upgrade│───▶│  Rollback   │
│   Checks     │    │  Baseline   │    │   Clone     │    │ Production  │    │ Validation  │    │  (if needed)│
└─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘    └─────────────┘
 01_preflight       02_clone            03_validate        04_upgrade         05_post_upgrade    06_rollback
```

Each phase produces queryable output. No phase proceeds without the prior phase passing.

## Quickstart

```bash
# 1. Set your target table
export ICEBERG_DB="MY_DATABASE"
export ICEBERG_SCHEMA="MY_SCHEMA"
export ICEBERG_TABLE="MY_ICEBERG_TABLE"

# 2. Run the full upgrade pipeline
./scripts/run_upgrade.sh

# Or run individual phases:
# snowsql -f sql/01_preflight_checks.sql -D db=$ICEBERG_DB -D schema=$ICEBERG_SCHEMA -D table=$ICEBERG_TABLE
```

## Repository Map

```
iceberg-v3-upgrade/
├── README.md                            ← You are here
├── CONTRIBUTING.md                      ← How to contribute
├── CHANGELOG.md                         ← Release history
├── LICENSE                              ← Apache 2.0
│
├── docs/
│   ├── architecture.md                  ← ADR: clone-validate-upgrade pattern
│   ├── runbook.md                       ← Operator step-by-step procedure
│   └── rollback-plan.md                 ← Rollback decision tree
│
├── sql/
│   ├── 01_preflight_checks.sql          ← Eligibility, dependencies, grants
│   ├── 02_clone_and_baseline.sql        ← Zero-copy clone, baseline metrics
│   ├── 03_validate_clone.sql            ← Workload validation on clone
│   ├── 04_upgrade.sql                   ← Production ALTER + version confirm
│   ├── 05_post_upgrade_validation.sql   ← Downstream health checks
│   └── 06_rollback.sql                  ← Time Travel restore
│
├── scripts/
│   ├── run_upgrade.sh                   ← Orchestrator with go/no-go gates
│   └── generate_dependency_report.py    ← Dependency graph builder
│
├── tests/
│   ├── test_preflight.sql               ← Pre-flight assertion queries
│   └── test_post_upgrade.sql            ← Post-upgrade assertion queries
│
├── templates/
│   ├── upgrade_ticket.md                ← Change request template
│   └── validation_report.md             ← Post-upgrade sign-off
│
└── .github/
    └── ISSUE_TEMPLATE/
        └── upgrade_request.md           ← GitHub issue template
```

## Prerequisites

- Snowflake account with Iceberg tables (Snowflake-managed storage)
- Role with `OWNERSHIP` or `MANAGE GRANTS` on the target table
- Warehouse sized appropriately for validation workloads
- Time Travel retention ≥ 1 day on the target table (for rollback)
- `snowsql` or Snowsight worksheet access

## Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Clone-first validation | The v3 upgrade is permanent. Zero-copy clones let you rehearse without touching production data. |
| Dependency graph before upgrade | A table's downstream objects (streams, dynamic tables, views) carry implicit v2 assumptions. Discovery must happen before the ALTER. |
| Go/no-go gates | Each phase must pass before the next begins. This prevents partial upgrades in ambiguous states. |
| Time Travel as rollback | The upgrade is irreversible at the metadata level. Time Travel is the only restore path for Snowflake-managed tables. |
| Queryable output at every step | Every script writes results to temporary tables or produces SELECT output. No silent steps. |

## What This Toolkit Does NOT Do

- It does not upgrade tables managed by external catalogs (Glue, Polaris, etc.)
- It does not handle cross-region replication concerns
- It does not automate external engine compatibility testing (Spark, Trino, etc.) — it flags the need for it
- It does not replace Snowflake documentation — it operationalizes it

## References

- [Snowflake: Upgrade Iceberg table version](https://docs.snowflake.com/en/user-guide/tables-iceberg-configure#upgrade-the-apache-iceberg-version-for-a-table)
- [Apache Iceberg v3 spec](https://iceberg.apache.org/spec/)
- [Snowflake: Zero-copy cloning](https://docs.snowflake.com/en/sql-reference/sql/create-clone)

## License

Apache 2.0 — see [LICENSE](LICENSE).
