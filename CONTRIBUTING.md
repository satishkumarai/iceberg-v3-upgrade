# Contributing

## How to Contribute

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-improvement`)
3. Make your changes
4. Test against a non-production Snowflake environment
5. Submit a pull request

## Guidelines

- All SQL must be idempotent where possible (CREATE OR REPLACE, IF NOT EXISTS)
- Every script must produce queryable output — no silent operations
- Use fully qualified object names (`database.schema.object`)
- Variable substitution uses `&{var}` for SnowSQL or session variables
- Test on a clone before modifying production scripts

## Code Style

- SQL: uppercase keywords, lowercase identifiers, 4-space indentation
- Python: PEP 8, type hints, docstrings on public functions
- Bash: `set -euo pipefail`, quote all variables, use `shellcheck`
- Markdown: one sentence per line for clean diffs

## Reporting Issues

Use the [upgrade request template](.github/ISSUE_TEMPLATE/upgrade_request.md) for new table upgrade requests.
Use standard GitHub issues for bugs or improvements to the toolkit itself.
