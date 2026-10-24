#!/usr/bin/env bash
# run_upgrade.sh — Orchestrator for Iceberg v2→v3 upgrade pipeline
#
# Runs all SQL phases in sequence with go/no-go gates between them.
# Requires: snowsql, bash 4+
#
# Usage:
#   export ICEBERG_DB="MY_DATABASE"
#   export ICEBERG_SCHEMA="MY_SCHEMA"
#   export ICEBERG_TABLE="MY_ICEBERG_TABLE"
#   export SNOWSQL_ACCOUNT="my_account"    # or use ~/.snowsql/config
#   export SNOWSQL_USER="my_user"          # or use ~/.snowsql/config
#   ./scripts/run_upgrade.sh
#
# Options:
#   --dry-run        Run pre-flight only, do not proceed
#   --skip-to N      Skip to phase N (use with caution, for resuming)
#   --auto-approve   Skip interactive go/no-go prompts (CI mode)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="${SCRIPT_DIR}/../sql"
LOG_DIR="${SCRIPT_DIR}/../logs"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOG_FILE="${LOG_DIR}/upgrade_${TIMESTAMP}.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Defaults
DRY_RUN=false
SKIP_TO=1
AUTO_APPROVE=false

# Parse args
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)      DRY_RUN=true; shift ;;
        --skip-to)      SKIP_TO="$2"; shift 2 ;;
        --auto-approve) AUTO_APPROVE=true; shift ;;
        *)              echo "Unknown option: $1"; exit 1 ;;
    esac
done

# Validate environment
for var in ICEBERG_DB ICEBERG_SCHEMA ICEBERG_TABLE; do
    if [[ -z "${!var:-}" ]]; then
        echo -e "${RED}ERROR: $var is not set.${NC}"
        echo "Usage: export $var='...' && ./scripts/run_upgrade.sh"
        exit 1
    fi
done

mkdir -p "$LOG_DIR"

log() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    echo -e "$msg" | tee -a "$LOG_FILE"
}

run_sql() {
    local phase_name="$1"
    local sql_file="$2"

    log "${GREEN}=== Running: $phase_name ===${NC}"
    log "SQL file: $sql_file"
    log "Table: ${ICEBERG_DB}.${ICEBERG_SCHEMA}.${ICEBERG_TABLE}"

    snowsql \
        -f "$sql_file" \
        -D "iceberg_db=${ICEBERG_DB}" \
        -D "iceberg_schema=${ICEBERG_SCHEMA}" \
        -D "iceberg_table=${ICEBERG_TABLE}" \
        -o output_format=plain \
        -o header=true \
        -o timing=true \
        2>&1 | tee -a "$LOG_FILE"

    local exit_code=${PIPESTATUS[0]}
    if [[ $exit_code -ne 0 ]]; then
        log "${RED}FAILED: $phase_name exited with code $exit_code${NC}"
        return 1
    fi

    log "${GREEN}COMPLETED: $phase_name${NC}"
    return 0
}

gate() {
    local phase_name="$1"

    if [[ "$AUTO_APPROVE" == "true" ]]; then
        log "${YELLOW}AUTO-APPROVED: $phase_name${NC}"
        return 0
    fi

    echo ""
    echo -e "${YELLOW}=== GO/NO-GO GATE: $phase_name ===${NC}"
    echo "Review the output above. All checks must pass before proceeding."
    echo ""
    read -rp "Proceed to next phase? [y/N/rollback] " answer

    case "$answer" in
        y|Y|yes|YES)
            log "GATE PASSED: $phase_name (operator approved)"
            return 0
            ;;
        rollback|ROLLBACK)
            log "${RED}ROLLBACK REQUESTED at gate: $phase_name${NC}"
            run_sql "Phase 6: Rollback" "${SQL_DIR}/06_rollback.sql"
            exit 1
            ;;
        *)
            log "${RED}GATE REJECTED: $phase_name (operator declined)${NC}"
            echo "Upgrade aborted. No changes made to production."
            exit 1
            ;;
    esac
}

# ============================================================================
# MAIN PIPELINE
# ============================================================================

log "=== Iceberg v2→v3 Upgrade Pipeline ==="
log "Target: ${ICEBERG_DB}.${ICEBERG_SCHEMA}.${ICEBERG_TABLE}"
log "Started: $(date)"
log "Dry run: ${DRY_RUN}"
log "Log file: ${LOG_FILE}"
echo ""

# Phase 1: Pre-flight
if [[ $SKIP_TO -le 1 ]]; then
    run_sql "Phase 1: Pre-flight Checks" "${SQL_DIR}/01_preflight_checks.sql"
    gate "Pre-flight → Clone"
fi

if [[ "$DRY_RUN" == "true" ]]; then
    log "${YELLOW}DRY RUN: Stopping after pre-flight.${NC}"
    exit 0
fi

# Phase 2: Clone and Baseline
if [[ $SKIP_TO -le 2 ]]; then
    run_sql "Phase 2: Clone and Baseline" "${SQL_DIR}/02_clone_and_baseline.sql"
    gate "Clone → Validate"
fi

# Phase 3: Validate Clone
if [[ $SKIP_TO -le 3 ]]; then
    run_sql "Phase 3: Validate Clone" "${SQL_DIR}/03_validate_clone.sql"
    gate "Validate → Upgrade Production"
fi

# Phase 4: Upgrade Production
if [[ $SKIP_TO -le 4 ]]; then
    log "${RED}=== PRODUCTION UPGRADE — THIS IS PERMANENT ===${NC}"
    if [[ "$AUTO_APPROVE" != "true" ]]; then
        read -rp "Final confirmation: upgrade ${ICEBERG_DB}.${ICEBERG_SCHEMA}.${ICEBERG_TABLE} to v3? [yes/NO] " confirm
        if [[ "$confirm" != "yes" ]]; then
            log "Upgrade aborted by operator at final confirmation."
            exit 1
        fi
    fi
    run_sql "Phase 4: Upgrade Production" "${SQL_DIR}/04_upgrade.sql"
    gate "Upgrade → Post-Upgrade Validation"
fi

# Phase 5: Post-Upgrade Validation
if [[ $SKIP_TO -le 5 ]]; then
    run_sql "Phase 5: Post-Upgrade Validation" "${SQL_DIR}/05_post_upgrade_validation.sql"
fi

log ""
log "${GREEN}=== UPGRADE PIPELINE COMPLETE ===${NC}"
log "Table: ${ICEBERG_DB}.${ICEBERG_SCHEMA}.${ICEBERG_TABLE}"
log "Status: Upgraded to Iceberg v3"
log "Next: Enter monitoring period (24-72h). See docs/runbook.md."
log "Rollback: If issues found, run sql/06_rollback.sql with pre_upgrade_ts from Phase 4 output."
log "Log: ${LOG_FILE}"
