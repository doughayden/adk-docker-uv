# Development

This document covers development workflows, code quality standards, and testing.

## Prerequisites

- Python 3.13+
- `uv` package manager
- Google Cloud SDK (gcloud CLI) for Vertex AI authentication

## Template Initialization

**If you created this repository from the template**, initialize it once after cloning:

```bash
# Preview changes without making them
uv run init_template.py --dry-run

# Apply changes
uv run init_template.py
```

This script:
- Renames the package to match your repository name
- Updates all configuration, documentation, and test files
- Resets `CHANGELOG.md` with a fresh template
- Regenerates the UV lockfile

After running, review changes with `git status` and commit:

```bash
git add -A
git commit -m "chore: initialize from template"
```

The script creates `init_template_results.md` as an audit log of changes. Dry-run mode creates `init_template_dry_run.md` instead. Both are gitignored.

## Development Commands

### Running the Server

```bash
# Configure authentication first
cp .env.example .env
# Edit .env to set GOOGLE_CLOUD_PROJECT and GOOGLE_CLOUD_LOCATION
# Authenticate: gcloud auth application-default login

# Run server (default)
uv run server

# Enable web UI by setting SERVE_WEB_INTERFACE=true in .env
```

**Debug mode** (detailed logging):
```bash
LOG_LEVEL=DEBUG uv run server
```

### Docker Compose (Local Development)

**Recommended workflow** for containerized local development:

```bash
# Start with hot reloading (recommended)
docker compose up --build --watch
```

This provides:
- Automatic file syncing for `src/` changes (instant)
- Automatic rebuilds for dependency changes
- Isolated environment matching production

For complete Docker Compose workflow documentation, see [Docker Compose Workflow Guide](./docker-compose-workflow.md).

### Code Quality

Run all checks before committing:

```bash
# Format code
uv run ruff format

# Lint code
uv run ruff check

# Type check
uv run mypy
```

**One-liner** for all checks:
```bash
uv run ruff format && uv run ruff check && uv run mypy
```

### Testing

```bash
# Run all tests
uv run pytest -v

# Run tests with coverage
uv run pytest --cov --cov-report=term-missing

# Run specific test file
uv run pytest tests/test_integration.py -v

# Run specific test
uv run pytest tests/test_integration.py::test_agent_uses_instruction_provider_callable -v
```

## Code Quality Standards

### Type Hints

- **Strict mypy checking enabled** - all functions must have complete type annotations
- **Modern Python syntax** - uses Python 3.13+ features (PEP 604 union types with `|`, lowercase generics)
- **Type-safe models** - Pydantic for runtime validation

Example:
```python
def example_tool(tool_context: ToolContext) -> dict[str, Any]:
    """Example tool with full type safety."""
    ...
```

### Code Style

**Ruff configuration:** Auto-fix enabled, 88-char line length (see `pyproject.toml` for complete rule list)

**Pathlib usage**:
- Use `Path` objects for all file operations (enforced by ruff PTH rules)
- Never use `os.path` functions

Example:
```python
from pathlib import Path

# Good
data_file = Path("data/config.json")
if data_file.exists():
    content = data_file.read_text()

# Bad - will be flagged by ruff
import os
if os.path.exists("data/config.json"):
    with open("data/config.json") as f:
        content = f.read()
```

### Docstrings

- **Comprehensive module, class, and function docstrings**
- **Include**: arguments, exceptions, return values
- **Google-style docstring format**

Example:
```python
def example_tool(tool_context: ToolContext) -> dict[str, Any]:
    """Example tool that logs a success message.

    This is a placeholder example tool. Replace with actual implementation.

    Args:
        tool_context: ADK ToolContext with access to session state

    Returns:
        A dictionary with status and message about the logging operation.
    """
    ...
```

### Testing

- **100% coverage** on all production code (scripts and server.py excluded)
- **Organized by feature** - tests in separate files, shared fixtures in `conftest.py`
- **pytest fixtures** - reusable fixtures in `conftest.py` to eliminate patching in individual tests
- **Duck-typed mocks** - minimal mock classes that satisfy ADK protocols

Test organization:
```
tests/
  conftest.py              # Shared fixtures
  test_*.py                # Test modules organized by feature
```

## Dependencies

**Runtime:** Google ADK, pydantic, python-dotenv

**Development:** pytest, ruff, mypy (see `pyproject.toml` for complete list)

**PEP 735 dependency groups:** Dev tools in `dev` group, installed by default with `uv run`

## Project Structure

```
adk-docker-uv/
  src/adk_docker_uv/
    agent.py              # LlmAgent configuration
    callbacks.py          # Agent callbacks
    prompt.py             # Agent prompts
    tools.py              # Custom tools
    server.py             # FastAPI development server
    utils/                # Utilities
      env_parser.py         # Environment variable parsing
      log_config.py         # Logging configuration
  tests/                  # Test suite
    conftest.py             # Shared fixtures
    test_integration.py     # Integration tests
    test_*.py               # Unit tests
  docs/                   # Documentation
  .env.example            # Environment template
  pyproject.toml          # Project configuration
  CLAUDE.md               # Project instructions
  README.md               # Main documentation
```

## CI/CD

GitHub Actions runs code quality checks and tests on every push/PR. See [CI/CD Workflow Guide](./cicd-setup.md) for complete automation details.

## Dependency Management

**No manual sync needed**: `uv run` handles dependency installation automatically.

**Adding dependencies**:
```bash
# Add runtime dependency
uv add package-name

# Add dev dependency
uv add --group dev package-name
```

**Updating dependencies**:
```bash
# Update all dependencies
uv lock --upgrade

# Update specific package
uv lock --upgrade-package package-name
```

## Observability

OpenTelemetry integration with Google Cloud Trace and Cloud Logging.

**Control log level:**
```bash
LOG_LEVEL=DEBUG uv run server
```

**View traces and logs:**
- Google Cloud Console: [Cloud Trace](https://console.cloud.google.com/traces) and [Logs Explorer](https://console.cloud.google.com/logs)
- gcloud CLI: `gcloud logging tail "logName:projects/{PROJECT_ID}/logs/{AGENT_NAME}-otel-logs"`
- VS Code: Install [Google Cloud Code extension](https://cloud.google.com/code/docs/vscode/install)

See [docs/observability.md](observability.md) for complete configuration and usage details.
