# Repository Guidelines

## Project Structure & Module Organization

Application code is under `src/arize_upgrade/`, with `cli.py` as the workflow-facing entry point. Core modules handle release parsing (`releases.py`), version comparison (`versions.py`), bundle validation (`bundle.py`), deployment state (`state.py`), and provider-neutral messages (`messages.py`). Notification adapters live in `src/arize_upgrade/notify/` for Slack, Slack webhooks, and Teams. Tests are in `tests/`, with release fixtures in `tests/fixtures/`. Operational scripts are in `scripts/`; the checked-in deployment configuration is the root `values.yaml`. GitHub Actions definitions are in `.github/workflows/`.

## Build, Test, and Development Commands

Set up a development environment with:

```bash
python3 -m venv .venv
.venv/bin/pip install -e ".[dev]"
```

Run the full suite with `.venv/bin/pytest -q`. Run a focused file or test with, for example, `.venv/bin/pytest tests/test_state.py -q` or `.venv/bin/pytest tests/test_state.py::test_completed_runs_do_not_count -q`. Check the workflow CLI with `.venv/bin/arize-upgrade --help`. Shell behavior can be tested with `bash tests/test_render_values.sh`; do not run deployment scripts against production merely to test them.

## Coding Style & Naming Conventions

Use Python 3.11-compatible, standard-library-first code with four-space indentation, type hints, focused functions, and `snake_case` names. Use `PascalCase` for classes and descriptive `UPPER_CASE` constants. No formatter or linter is configured, so keep changes readable and consistent with nearby code. Shell scripts should use Bash, `set -euo pipefail`, quoted variables, and fail-closed validation.

## Testing Guidelines

Pytest discovers tests under `tests/`; test files use `test_*.py`, and test functions use `test_*`. Keep external boundaries injectable (`fetch`, `post`, and `run`) so tests remain offline and never contact AWS, a cluster, vendor endpoints, or chat providers. Add regression tests for parsing, version guards, provider symmetry, and failure-safe behavior when changing those areas.

## Commit & Pull Request Guidelines

Use short imperative conventional-style subjects with a scope, matching history such as `docs: ...`, `config: ...`, and `ci: ...` (for example, `config: pin ...`). Keep commits focused. Pull requests should explain operational impact, identify workflow/configuration changes, include test commands and results, link the relevant issue or design document, and include screenshots or sample notification output when changing chat messages or workflow UX. Call out any required GitHub Variables, Secrets, or Environment reviewers.

## Security & Configuration Tips

`values.yaml` is intentionally checked in but must contain no credentials, JWTs, or private keys. Keep sensitive values out of Git and preserve the pre-commit hook. Preserve `arize.sh -y -q`, bundle-version verification, cluster-ARN validation, approval environments, and fail-safe concurrency checks unless the operational design is deliberately revised.
