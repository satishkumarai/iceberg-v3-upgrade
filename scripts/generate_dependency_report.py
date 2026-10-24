#!/usr/bin/env python3
"""generate_dependency_report.py — Build a dependency graph for an Iceberg table.

Queries Snowflake ACCOUNT_USAGE.OBJECT_DEPENDENCIES, POLICY_REFERENCES,
and SHOW commands to produce a full dependency report for upgrade planning.

Usage:
    export SNOWFLAKE_ACCOUNT='my_account'
    export SNOWFLAKE_USER='my_user'
    export SNOWFLAKE_WAREHOUSE='my_warehouse'
    python3 scripts/generate_dependency_report.py MY_DATABASE MY_SCHEMA MY_TABLE

Output:
    Writes a JSON report to reports/<table>_dependency_report_<timestamp>.json
    and a human-readable summary to stdout.
"""

import json
import os
import sys
from datetime import datetime, timezone
from typing import Any


def get_connection():
    """Create a Snowflake connection using snowflake-connector-python."""
    try:
        import snowflake.connector
    except ImportError:
        print("ERROR: snowflake-connector-python is required.")
        print("Install: pip install snowflake-connector-python")
        sys.exit(1)

    return snowflake.connector.connect(
        account=os.environ.get("SNOWFLAKE_ACCOUNT", ""),
        user=os.environ.get("SNOWFLAKE_USER", ""),
        password=os.environ.get("SNOWFLAKE_PASSWORD", ""),
        warehouse=os.environ.get("SNOWFLAKE_WAREHOUSE", ""),
        authenticator=os.environ.get("SNOWFLAKE_AUTHENTICATOR", "snowflake"),
    )


def query(conn, sql: str, params: dict | None = None) -> list[dict[str, Any]]:
    """Execute a query and return results as a list of dicts."""
    cur = conn.cursor()
    try:
        if params:
            cur.execute(sql, params)
        else:
            cur.execute(sql)
        columns = [desc[0] for desc in cur.description] if cur.description else []
        return [dict(zip(columns, row)) for row in cur.fetchall()]
    finally:
        cur.close()


def get_iceberg_info(conn, fqn: str) -> dict:
    """Get Iceberg table metadata."""
    rows = query(conn, f"""
        SELECT SYSTEM$GET_ICEBERG_TABLE_INFORMATION('{fqn}') AS info
    """)
    if rows:
        return json.loads(rows[0]["INFO"])
    return {}


def get_object_dependencies(conn, fqn: str) -> list[dict]:
    """Get all objects that depend on this table."""
    return query(conn, f"""
        SELECT
            referencing_object_name     AS dependent_object,
            referencing_object_domain   AS dependent_type,
            referencing_database        AS dependent_database,
            referencing_schema          AS dependent_schema
        FROM TABLE(
            SNOWFLAKE.ACCOUNT_USAGE.OBJECT_DEPENDENCIES(
                OBJECT_NAME   => '{fqn}',
                OBJECT_DOMAIN => 'TABLE'
            )
        )
        ORDER BY referencing_object_domain, referencing_object_name
    """)


def get_policies(conn, fqn: str) -> list[dict]:
    """Get all policies attached to the table."""
    return query(conn, f"""
        SELECT
            policy_name,
            policy_kind,
            policy_db,
            policy_schema,
            ref_column_name
        FROM TABLE(SNOWFLAKE.INFORMATION_SCHEMA.POLICY_REFERENCES(
            REF_ENTITY_NAME   => '{fqn}',
            REF_ENTITY_DOMAIN => 'TABLE'
        ))
        ORDER BY policy_kind, policy_name
    """)


def get_grants(conn, db: str, schema: str, table: str) -> list[dict]:
    """Get all grants on the table."""
    query(conn, f"SHOW GRANTS ON TABLE {db}.{schema}.{table}")
    return query(conn, """
        SELECT "privilege", "grantee_name", "grant_option", "granted_by"
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
    """)


def get_streams(conn, db: str, schema: str, table: str) -> list[dict]:
    """Get streams on this table."""
    fqn = f"{db}.{schema}.{table}"
    query(conn, f"SHOW STREAMS IN SCHEMA {db}.{schema}")
    return query(conn, f"""
        SELECT "name", "type", "stale", "stale_after", "mode", "owner"
        FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()))
        WHERE "table_name" = '{fqn}'
    """)


def main():
    if len(sys.argv) != 4:
        print(f"Usage: {sys.argv[0]} <database> <schema> <table>")
        sys.exit(1)

    db, schema, table = sys.argv[1], sys.argv[2], sys.argv[3]
    fqn = f"{db}.{schema}.{table}"

    print(f"Generating dependency report for: {fqn}")
    print("=" * 60)

    conn = get_connection()

    report: dict[str, Any] = {
        "table": fqn,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "generated_by": os.environ.get("SNOWFLAKE_USER", "unknown"),
    }

    # Iceberg metadata
    print("  Checking Iceberg metadata...")
    report["iceberg_info"] = get_iceberg_info(conn, fqn)

    # Dependencies
    print("  Discovering dependencies...")
    deps = get_object_dependencies(conn, fqn)
    report["dependencies"] = deps
    report["dependency_summary"] = {}
    for dep in deps:
        dep_type = dep["DEPENDENT_TYPE"]
        report["dependency_summary"][dep_type] = report["dependency_summary"].get(dep_type, 0) + 1

    # Policies
    print("  Checking policies...")
    report["policies"] = get_policies(conn, fqn)

    # Grants
    print("  Checking grants...")
    report["grants"] = get_grants(conn, db, schema, table)

    # Streams
    print("  Checking streams...")
    report["streams"] = get_streams(conn, db, schema, table)

    conn.close()

    # Write report
    os.makedirs("reports", exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    report_path = f"reports/{table}_dependency_report_{timestamp}.json"
    with open(report_path, "w") as f:
        json.dump(report, f, indent=2, default=str)

    # Print summary
    print()
    print("=" * 60)
    print(f"TABLE:           {fqn}")
    print(f"ICEBERG VERSION: {report['iceberg_info'].get('iceberg_version', 'unknown')}")
    print()
    print("DEPENDENCY SUMMARY:")
    for dep_type, count in sorted(report.get("dependency_summary", {}).items()):
        print(f"  {dep_type}: {count}")
    if not report.get("dependency_summary"):
        print("  (none found)")
    print()
    print(f"POLICIES:        {len(report.get('policies', []))}")
    print(f"GRANTS:          {len(report.get('grants', []))}")
    print(f"STREAMS:         {len(report.get('streams', []))}")
    print()
    print(f"Full report: {report_path}")
    print("=" * 60)


if __name__ == "__main__":
    main()
