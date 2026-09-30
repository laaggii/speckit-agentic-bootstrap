# agentic-bootstrap

Interactive bootstrap for creating reproducible Spec Kit based Python projects.

Supports:

- Claude Code
- OpenAI Codex
- OpenCode
- LM Studio local models
- GitHub Spec Kit
- uv
- pytest
- Ruff
- mypy
- pre-commit
- GitHub Actions

## Usage

```bash
git clone git@github.com:laaggii/agentic-bootstrap.git
cd agentic-bootstrap

./bootstrap.sh my-project
```

The installer:

1. checks and installs dependencies;
2. creates a Python/uv project;
3. initializes Spec Kit;
4. lets you choose provider + model for:
   - Analyst
   - Architect
   - Tester
   - Planner
   - Coder
   - Reviewer
5. installs required Spec Kit integrations;
6. creates project-level agent configuration;
7. configures local project trust;
8. creates CI and pre-commit;
9. generates a reusable Spec Kit workflow;
10. creates the initial Git commit.

## Generated routing

The selected provider/model routing is stored in:

```text
.agentic/providers.json
```

Example:

```json
{
  "schema_version": 1,
  "roles": {
    "analyst": {
      "integration": "codex",
      "model": ""
    },
    "architect": {
      "integration": "codex",
      "model": ""
    },
    "tester": {
      "integration": "codex",
      "model": ""
    },
    "planner": {
      "integration": "codex",
      "model": ""
    },
    "coder": {
      "integration": "opencode",
      "model": "lmstudio/qwen/qwen3.5-9b"
    },
    "reviewer": {
      "integration": "codex",
      "model": ""
    }
  }
}
```

## Workflow

After creating and clarifying a feature spec:

```bash
specify workflow validate ./workflows/agent-track.yml
specify workflow run ./workflows/agent-track.yml
```

The generated workflow follows this pipeline:

```text
Architect
  ↓
verify plan
  ↓
human gate
  ↓
independent Tester
  ↓
verify tests + RED phase
  ↓
human gate
  ↓
Planner
  ↓
Analyze
  ↓
human gate
  ↓
Coder
  ↓
verify acceptance contract unchanged
  ↓
deterministic CI
  ↓
Converge
  ↓
Reviewer
  ↓
human gate
```

## Development flow

The requirements phase is intentionally interactive.

Use your configured Analyst integration to create and clarify the feature specification.

### Claude Code

```text
/speckit.specify
/speckit.clarify
```

### Codex

```text
$speckit-specify
$speckit-clarify
```

After the specification is approved, commit it and run the workflow:

```bash
git add .
git commit -m "spec: define feature"

specify workflow validate ./workflows/agent-track.yml
specify workflow run ./workflows/agent-track.yml
```

## CI

Run the deterministic local CI pipeline with:

```bash
make ci
```

The generated project uses:

- Ruff formatting checks
- Ruff linting
- mypy
- pytest

## Provider configuration

### Claude Code

Shared project configuration:

```text
.claude/settings.json
```

Machine-local trust is completed once through the normal Claude CLI trust prompt.

### OpenAI Codex

Shared project configuration:

```text
.codex/config.toml
```

Machine-local project trust is stored under:

```text
~/.codex/config.toml
```

A trusted project entry looks like:

```toml
[projects."/absolute/path/to/project"]
trust_level = "trusted"
```

### OpenCode

Shared project configuration:

```text
opencode.jsonc
```

OpenCode can use hosted providers or local models exposed by LM Studio.

For example:

```text
lmstudio/qwen/qwen3.5-9b
```

## LM Studio

If LM Studio is installed and its local server is running, OpenCode can discover local models automatically.

Check available models with:

```bash
opencode models
```

Example:

```text
lmstudio/qwen/qwen3.5-9b
opencode/big-pickle
opencode/ling-3.0-flash-fin-free
```

## Trust model

Project behavior is version-controlled.

Machine trust is not.

This keeps the repository reproducible without allowing a cloned repository to silently mark itself trusted on another machine.

Typical split:

```text
.claude/settings.json
→ shared Claude project behavior

.codex/config.toml
→ shared Codex sandbox / approval behavior

opencode.jsonc
→ shared OpenCode provider / permission behavior

~/.codex/config.toml
→ machine-local Codex trust

Claude CLI trust prompt
→ machine-local Claude trust
```

## Security

The bootstrap does not write secrets, API keys, or credentials into the repository.

Generated project configs are intended to keep agents inside the working project and prevent unattended actions such as:

- `git push`
- `git commit`
- `sudo`
- destructive recursive deletion

Review generated permissions before using the bootstrap in sensitive repositories.

## GitHub

The bootstrap can optionally create and push the generated project using GitHub CLI.

If needed, authenticate first:

```bash
gh auth login
```

Then the generated project can be published with:

```bash
gh repo create <project-name> \
  --private \
  --source=. \
  --remote=origin \
  --push
```

## Recommended role split

A useful default setup is:

```text
Analyst     → Codex
Architect   → Codex
Tester      → Codex
Planner     → Codex
Coder       → OpenCode + LM Studio
Reviewer    → Codex
```

This keeps reasoning-heavy stages on a strong cloud model while implementation can run on a local coding model.

The routing is fully configurable during bootstrap.
