# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [1.0.0] - 2026-10-18

### Added
- 6-phase SQL upgrade pipeline: pre-flight, clone, validate, upgrade, post-upgrade, rollback
- Bash orchestrator (`run_upgrade.sh`) with go/no-go gates and `--dry-run` support
- Python dependency report generator (`generate_dependency_report.py`)
- Architecture decision record for clone-validate-upgrade pattern
- Operator runbook with phase-by-phase procedures
- Rollback plan with decision tree and Time Travel restore procedure
- Pre-flight and post-upgrade SQL assertion tests
- GitHub issue template for upgrade requests
- Change request and validation report templates
