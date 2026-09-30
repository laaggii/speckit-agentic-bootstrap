#!/usr/bin/env bash

set -euo pipefail

# ============================================================
# agentic-bootstrap
# macOS-first bootstrap for:
#
#   Spec Kit
#   Claude Code
#   OpenAI Codex
#   OpenCode
#   LM Studio
#   uv
#   pytest / ruff / mypy / pre-commit
#
# Roles:
#
#   Analyst
#   Architect
#   Tester
#   Planner
#   Coder
#   Reviewer
# ============================================================


# ------------------------------------------------------------
# UI
# ------------------------------------------------------------

RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
GREEN="\033[32m"
YELLOW="\033[33m"
RED="\033[31m"
CYAN="\033[36m"

info() {
  printf "${CYAN}▶ %s${RESET}\n" "$*"
}

ok() {
  printf "${GREEN}✓ %s${RESET}\n" "$*"
}

warn() {
  printf "${YELLOW}! %s${RESET}\n" "$*"
}

die() {
  printf "${RED}ERROR: %s${RESET}\n" "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

confirm() {
  local prompt="$1"
  local default="${2:-y}"
  local answer=""

  if [[ "$default" == "y" ]]; then
    printf "%s [Y/n]: " "$prompt" >&2
  else
    printf "%s [y/N]: " "$prompt" >&2
  fi

  read -r answer </dev/tty || true
  answer="${answer:-$default}"

  case "$answer" in
    y|Y|yes|YES)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

ask() {
  local prompt="$1"
  local default="${2:-}"
  local answer=""

  if [[ -n "$default" ]]; then
    printf "%s [%s]: " "$prompt" "$default" >&2
  else
    printf "%s: " "$prompt" >&2
  fi

  read -r answer </dev/tty || true
  printf "%s" "${answer:-$default}"
}

canonical_path() {
  cd "$1"
  pwd -P
}

json_quote() {
  printf "%s" "$1" | jq -Rs .
}


# ------------------------------------------------------------
# HOMEBREW + BASE TOOLS
# ------------------------------------------------------------

install_homebrew() {
  if have brew; then
    ok "Homebrew already installed"
    return
  fi

  warn "Homebrew is not installed"

  if ! confirm "Install Homebrew now?"; then
    die "Homebrew is required for automatic dependency installation"
  fi

  /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  have brew || die "Homebrew installation finished but brew is not on PATH"
}

brew_install_if_missing() {
  local command="$1"
  local package="$2"

  if have "$command"; then
    ok "$command already installed"
    return
  fi

  info "Installing $package..."
  brew install "$package"
}

install_base_tools() {
  printf "\n${BOLD}Base toolchain${RESET}\n\n"

  install_homebrew

  brew_install_if_missing git git
  brew_install_if_missing jq jq
  brew_install_if_missing gh gh
  brew_install_if_missing uv uv

  if have specify; then
    ok "Spec Kit already installed"
  else
    info "Installing Spec Kit..."
    uv tool install specify-cli
    hash -r
  fi

  have specify || {
    warn "specify not visible yet; updating shell path"
    uv tool update-shell || true
    export PATH="$HOME/.local/bin:$PATH"
  }

  have specify || die "Spec Kit install failed"

  ok "Base toolchain ready"
}


# ------------------------------------------------------------
# AGENT RUNTIMES
# ------------------------------------------------------------

install_claude() {
  if have claude; then
    ok "Claude Code already installed"
    return
  fi

  if ! confirm "Claude Code is missing. Install it?" "y"; then
    return
  fi

  if ! have npm; then
    info "Installing Node.js..."
    brew install node
  fi

  info "Installing Claude Code..."
  npm install -g @anthropic-ai/claude-code

  hash -r
}

install_codex() {
  if have codex; then
    ok "Codex CLI already installed"
    return
  fi

  if ! confirm "Codex CLI is missing. Install it?" "y"; then
    return
  fi

  if ! have npm; then
    info "Installing Node.js..."
    brew install node
  fi

  info "Installing Codex CLI..."
  npm install -g @openai/codex@latest

  hash -r
}

install_opencode() {
  if have opencode; then
    ok "OpenCode already installed"
    return
  fi

  if ! confirm "OpenCode is missing. Install OpenCode V2?" "y"; then
    return
  fi

  info "Installing OpenCode..."
  brew install anomalyco/tap/opencode-v2

  hash -r
}

detect_lms() {
  if have lms; then
    return 0
  fi

  if [[ -x "$HOME/.lmstudio/bin/lms" ]]; then
    export PATH="$HOME/.lmstudio/bin:$PATH"
    hash -r
  fi

  have lms
}

install_lmstudio_cli() {
  if detect_lms; then
    ok "LM Studio CLI already installed"
    return
  fi

  warn "LM Studio CLI (lms) not found"

  cat >&2 <<EOF

LM Studio is optional.
If you want a local OpenCode coder, install LM Studio first:

  https://lmstudio.ai/

Then enable the CLI in LM Studio or make sure this exists:

  ~/.lmstudio/bin/lms

EOF

  if confirm "Continue without LM Studio CLI?" "y"; then
    return
  fi

  die "Install LM Studio and rerun bootstrap"
}

install_agent_tools() {
  printf "\n${BOLD}Agent runtimes${RESET}\n\n"

  install_claude
  install_codex
  install_opencode
  install_lmstudio_cli
}


# ------------------------------------------------------------
# PROVIDER SELECTION
# ------------------------------------------------------------

provider_available() {
  case "$1" in
    claude)
      have claude
      ;;
    codex)
      have codex
      ;;
    opencode)
      have opencode
      ;;
    *)
      return 1
      ;;
  esac
}

first_available_reasoner() {
  if provider_available codex; then
    printf "codex"
  elif provider_available claude; then
    printf "claude"
  elif provider_available opencode; then
    printf "opencode"
  else
    die "No agent provider available"
  fi
}

first_available_coder() {
  if provider_available opencode; then
    printf "opencode"
  else
    first_available_reasoner
  fi
}

choose_provider() {
  local role="$1"
  local default="$2"

  local choices=()
  local provider=""
  local answer=""
  local i=1

  for provider in claude codex opencode; do
    if provider_available "$provider"; then
      choices+=("$provider")
    fi
  done

  if (( ${#choices[@]} == 0 )); then
    die "No providers installed"
  fi

  echo >&2
  printf "${BOLD}%s provider${RESET}\n" "$role" >&2

  for provider in "${choices[@]}"; do
    if [[ "$provider" == "$default" ]]; then
      printf "  %d) %-10s [default]\n" "$i" "$provider" >&2
    else
      printf "  %d) %s\n" "$i" "$provider" >&2
    fi

    i=$((i + 1))
  done

  printf "Choose provider [%s]: " "$default" >&2
  read -r answer </dev/tty || true

  if [[ -z "$answer" ]]; then
    printf "%s" "$default"
    return
  fi

  if [[ "$answer" =~ ^[0-9]+$ ]]; then
    local index=$((answer - 1))

    if (( index >= 0 && index < ${#choices[@]} )); then
      printf "%s" "${choices[$index]}"
      return
    fi
  fi

  for provider in "${choices[@]}"; do
    if [[ "$answer" == "$provider" ]]; then
      printf "%s" "$provider"
      return
    fi
  done

  die "Invalid provider: $answer"
}


# ------------------------------------------------------------
# MODEL SELECTION
# ------------------------------------------------------------

OPENCODE_MODELS=()

load_opencode_models() {
  OPENCODE_MODELS=()

  if ! have opencode; then
    return
  fi

  while IFS= read -r model; do
    [[ -n "$model" ]] && OPENCODE_MODELS+=("$model")
  done < <(opencode models 2>/dev/null || true)
}

choose_opencode_model() {
  local answer=""
  local model=""
  local default=""
  local i=1

  load_opencode_models

  if (( ${#OPENCODE_MODELS[@]} == 0 )); then
    warn "OpenCode returned no models" >&2
    ask "Enter OpenCode model ID"
    return
  fi

  # Prefer LM Studio if present.
  for model in "${OPENCODE_MODELS[@]}"; do
    if [[ "$model" == lmstudio/* ]]; then
      default="$model"
      break
    fi
  done

  [[ -z "$default" ]] && default="${OPENCODE_MODELS[0]}"

  echo >&2
  printf "${BOLD}OpenCode models${RESET}\n" >&2

  for model in "${OPENCODE_MODELS[@]}"; do
    if [[ "$model" == "$default" ]]; then
      printf "  %d) %-45s [default]\n" "$i" "$model" >&2
    else
      printf "  %d) %s\n" "$i" "$model" >&2
    fi

    i=$((i + 1))
  done

  echo "  c) custom model ID" >&2
  printf "Choose model [%s]: " "$default" >&2

  read -r answer </dev/tty || true

  if [[ -z "$answer" ]]; then
    printf "%s" "$default"
    return
  fi

  if [[ "$answer" == "c" ]]; then
    ask "Model ID"
    return
  fi

  if [[ "$answer" =~ ^[0-9]+$ ]]; then
    local index=$((answer - 1))

    if (( index >= 0 && index < ${#OPENCODE_MODELS[@]} )); then
      printf "%s" "${OPENCODE_MODELS[$index]}"
      return
    fi
  fi

  printf "%s" "$answer"
}

choose_model() {
  local role="$1"
  local provider="$2"

  case "$provider" in
    claude)
      ask "$role Claude model (blank = CLI default)" ""
      ;;

    codex)
      ask "$role Codex model (blank = CLI default)" ""
      ;;

    opencode)
      choose_opencode_model
      ;;

    *)
      die "Unknown provider: $provider"
      ;;
  esac
}


# ------------------------------------------------------------
# ROLE UTILITIES
# ------------------------------------------------------------

role_uses_provider() {
  local provider="$1"

  [[ "$ANALYST_PROVIDER" == "$provider" ]] ||
    [[ "$ARCHITECT_PROVIDER" == "$provider" ]] ||
    [[ "$TESTER_PROVIDER" == "$provider" ]] ||
    [[ "$PLANNER_PROVIDER" == "$provider" ]] ||
    [[ "$CODER_PROVIDER" == "$provider" ]] ||
    [[ "$REVIEWER_PROVIDER" == "$provider" ]]
}


# ------------------------------------------------------------
# CLAUDE PROJECT CONFIG
# ------------------------------------------------------------

write_claude_config() {
  mkdir -p .claude

  cat > .claude/settings.json <<'EOF'
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",

  "permissions": {
    "defaultMode": "acceptEdits",

    "deny": [
      "Bash(git push *)",
      "Bash(git commit *)"
    ]
  }
}
EOF

  ok "Created .claude/settings.json"
}


# ------------------------------------------------------------
# CLAUDE TRUST
# ------------------------------------------------------------

configure_claude_trust() {
  local project_dir="$1"

  project_dir="$(canonical_path "$project_dir")"

  echo
  printf "${BOLD}Claude project trust${RESET}\n"
  echo

  cat <<EOF
Claude Code keeps machine-local project trust separately from
the version-controlled .claude/settings.json.

The bootstrap will start Claude once in:

  $project_dir

Accept the trust prompt, then exit Claude.

EOF

  if ! confirm "Configure Claude trust now?" "y"; then
    warn "Skipping Claude trust"
    return
  fi

  (
    cd "$project_dir"

    echo
    echo "Claude will start now."
    echo
    echo "1. Accept the project trust dialog."
    echo "2. After Claude opens, type:"
    echo
    echo "     /exit"
    echo
    echo

    claude
  )

  ok "Claude trust/onboarding step completed"
}


# ------------------------------------------------------------
# CODEX PROJECT CONFIG
# ------------------------------------------------------------

write_codex_config() {
  mkdir -p .codex

  cat > .codex/config.toml <<'EOF'
approval_policy = "never"
sandbox_mode = "workspace-write"
EOF

  ok "Created .codex/config.toml"
}


# ------------------------------------------------------------
# CODEX TRUST
# ------------------------------------------------------------

configure_codex_trust() {
  local project_dir="$1"

  project_dir="$(canonical_path "$project_dir")"

  local codex_home="${CODEX_HOME:-$HOME/.codex}"
  local config="$codex_home/config.toml"

  echo
  printf "${BOLD}Codex project trust${RESET}\n"
  echo

  if ! confirm "Configure Codex trust for $project_dir?" "y"; then
    warn "Skipping Codex trust"
    return
  fi

  mkdir -p "$codex_home"
  touch "$config"

  python3 - "$config" "$project_dir" <<'PY'
import re
import sys
from pathlib import Path

config_path = Path(sys.argv[1])
project = sys.argv[2]

text = config_path.read_text()

escaped = (
    project
    .replace("\\", "\\\\")
    .replace('"', '\\"')
)

header = f'[projects."{escaped}"]'

lines = text.splitlines()
out: list[str] = []

i = 0
found = False

while i < len(lines):
    line = lines[i]

    if line.strip() == header:
        found = True
        out.append(header)
        out.append('trust_level = "trusted"')

        i += 1

        while i < len(lines):
            stripped = lines[i].strip()

            if stripped.startswith("[") and stripped.endswith("]"):
                break

            i += 1

        continue

    out.append(line)
    i += 1

if not found:
    if out and out[-1].strip():
        out.append("")

    out.append(header)
    out.append('trust_level = "trusted"')

config_path.write_text("\n".join(out).rstrip() + "\n")
PY

  ok "Codex trust configured"
}

verify_codex_trust() {
  local project_dir="$1"

  project_dir="$(canonical_path "$project_dir")"

  local config="${CODEX_HOME:-$HOME/.codex}/config.toml"

  if grep -Fq "[projects.\"$project_dir\"]" "$config" &&
    grep -A2 -F "[projects.\"$project_dir\"]" "$config" |
      grep -Fq 'trust_level = "trusted"'; then
    ok "Codex trusts $project_dir"
  else
    warn "Could not verify Codex trust entry"
    return 1
  fi
}


# ------------------------------------------------------------
# OPENCODE PROJECT CONFIG
# ------------------------------------------------------------

write_opencode_config() {
  local default_model="$1"

  cat > opencode.jsonc <<EOF
{
  "\$schema": "https://opencode.ai/config.json",

  "model": $(json_quote "$default_model"),

  "permissions": [
    {
      "action": "*",
      "resource": "*",
      "effect": "allow"
    },

    {
      "action": "external_directory",
      "resource": "*",
      "effect": "deny"
    },

    {
      "action": "read",
      "resource": ".env",
      "effect": "deny"
    },

    {
      "action": "read",
      "resource": ".env.*",
      "effect": "deny"
    },

    {
      "action": "shell",
      "resource": "git push *",
      "effect": "deny"
    },

    {
      "action": "shell",
      "resource": "git commit *",
      "effect": "deny"
    },

    {
      "action": "shell",
      "resource": "sudo *",
      "effect": "deny"
    },

    {
      "action": "shell",
      "resource": "rm -rf *",
      "effect": "deny"
    }
  ]
}
EOF

  ok "Created opencode.jsonc"
}


# ------------------------------------------------------------
# ROLE MANIFEST
# ------------------------------------------------------------

write_provider_manifest() {
  mkdir -p .agentic

  jq -n \
    --arg ap "$ANALYST_PROVIDER" \
    --arg am "$ANALYST_MODEL" \
    --arg arp "$ARCHITECT_PROVIDER" \
    --arg arm "$ARCHITECT_MODEL" \
    --arg tp "$TESTER_PROVIDER" \
    --arg tm "$TESTER_MODEL" \
    --arg pp "$PLANNER_PROVIDER" \
    --arg pm "$PLANNER_MODEL" \
    --arg cp "$CODER_PROVIDER" \
    --arg cm "$CODER_MODEL" \
    --arg rp "$REVIEWER_PROVIDER" \
    --arg rm "$REVIEWER_MODEL" \
    '{
      schema_version: 1,

      roles: {
        analyst: {
          integration: $ap,
          model: $am
        },

        architect: {
          integration: $arp,
          model: $arm
        },

        tester: {
          integration: $tp,
          model: $tm
        },

        planner: {
          integration: $pp,
          model: $pm
        },

        coder: {
          integration: $cp,
          model: $cm
        },

        reviewer: {
          integration: $rp,
          model: $rm
        }
      }
    }' > .agentic/providers.json

  ok "Created .agentic/providers.json"
}


# ------------------------------------------------------------
# PYTHON TOOLING
# ------------------------------------------------------------

write_makefile() {
  cat > Makefile <<'EOF'
.PHONY: format format-check lint typecheck test check ci

format:
	uv run ruff format .
	uv run ruff check --fix .

format-check:
	uv run ruff format --check .

lint:
	uv run ruff check .

typecheck:
	uv run mypy src

test:
	uv run pytest

check: format-check lint typecheck test

ci: check
EOF
}

append_pyproject_config() {
  cat >> pyproject.toml <<'EOF'


[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "-ra"


[tool.ruff]
line-length = 100
target-version = "py312"


[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B"]


[tool.mypy]
python_version = "3.12"
strict = true
files = ["src"]
EOF
}

write_precommit() {
  cat > .pre-commit-config.yaml <<'EOF'
repos:
  - repo: local
    hooks:
      - id: ruff-format
        name: Ruff format check
        entry: uv run ruff format --check
        language: system
        types_or: [python, pyi]

      - id: ruff-check
        name: Ruff lint
        entry: uv run ruff check
        language: system
        types_or: [python, pyi]
EOF
}

write_gitignore() {
  cat >> .gitignore <<'EOF'

# Python
__pycache__/
*.py[cod]

# Tool caches
.pytest_cache/
.mypy_cache/
.ruff_cache/
.coverage
htmlcov/

# Local environment
.env
.env.*
.venv/

# macOS
.DS_Store

# Agent-local state
.claude/settings.local.json

# Spec Kit run history
.specify/workflows/runs/
EOF
}


# ------------------------------------------------------------
# GITHUB ACTIONS
# ------------------------------------------------------------

write_ci() {
  mkdir -p .github/workflows

  cat > .github/workflows/ci.yml <<'EOF'
name: CI

on:
  pull_request:

  push:
    branches:
      - main

permissions:
  contents: read

jobs:
  ci:
    runs-on: ubuntu-latest

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Install uv
        uses: astral-sh/setup-uv@v6

      - name: Install dependencies
        run: uv sync --locked --all-groups

      - name: Run CI
        run: make ci
EOF
}


# ------------------------------------------------------------
# SPEC KIT
# ------------------------------------------------------------

install_spec_integrations() {
  local primary="$ANALYST_PROVIDER"
  local provider=""

  info "Initializing Spec Kit with '$primary'"

  specify init \
    --here \
    --force \
    --non-interactive \
    --integration "$primary" \
    --script py

  for provider in claude codex opencode; do
    [[ "$provider" == "$primary" ]] && continue

    if role_uses_provider "$provider"; then
      info "Installing Spec Kit integration: $provider"

      specify integration install \
        "$provider" \
        --script py
    fi
  done

  specify integration status
}


# ------------------------------------------------------------
# WORKFLOW HELPERS
# ------------------------------------------------------------

model_yaml_line() {
  local model="$1"

  if [[ -n "$model" ]]; then
    printf '    model: "%s"\n' "$model"
  fi
}


# ------------------------------------------------------------
# WORKFLOW
# ------------------------------------------------------------

write_agent_workflow() {
  mkdir -p workflows

  local architect_model_line=""
  local tester_model_line=""
  local planner_model_line=""
  local coder_model_line=""
  local reviewer_model_line=""

  [[ -n "$ARCHITECT_MODEL" ]] &&
    architect_model_line="$(model_yaml_line "$ARCHITECT_MODEL")"

  [[ -n "$TESTER_MODEL" ]] &&
    tester_model_line="$(model_yaml_line "$TESTER_MODEL")"

  [[ -n "$PLANNER_MODEL" ]] &&
    planner_model_line="$(model_yaml_line "$PLANNER_MODEL")"

  [[ -n "$CODER_MODEL" ]] &&
    coder_model_line="$(model_yaml_line "$CODER_MODEL")"

  [[ -n "$REVIEWER_MODEL" ]] &&
    reviewer_model_line="$(model_yaml_line "$REVIEWER_MODEL")"

  cat > workflows/agent-track.yml <<EOF
schema_version: "1.0"

workflow:
  id: "agent-track"
  name: "Agentic Development Track"
  version: "1.0.0"

  description: >
    Architecture -> independent acceptance tests ->
    planning -> analysis -> implementation ->
    deterministic CI -> convergence -> review.


requires:
  speckit_version: ">=1.0.0"

  integrations:
    any:
      - claude
      - codex
      - opencode


steps:

  # ==========================================================
  # PRE-FLIGHT
  # ==========================================================

  - id: preflight
    type: shell

    run: |
      set -eu

      BRANCH="\$(git branch --show-current)"
      FEATURE_DIR="specs/\$BRANCH"

      if [ ! -s "\$FEATURE_DIR/spec.md" ]; then
        echo "Cannot find active spec:"
        echo "  \$FEATURE_DIR/spec.md"
        exit 1
      fi

      echo "Active feature: \$FEATURE_DIR"


  # ==========================================================
  # ARCHITECT
  # ==========================================================

  - id: architect
    command: speckit.plan
    integration: $ARCHITECT_PROVIDER
$architect_model_line
    input:
      args: >
        Act as the Architect.

        Produce the smallest maintainable architecture that
        fully satisfies the already clarified specification.

        Prefer explicit boundaries and deterministic behavior.
        Avoid unnecessary abstractions.


  - id: verify-plan
    type: shell

    run: |
      set -eu

      FEATURE_DIR="specs/\$(git branch --show-current)"

      test -s "\$FEATURE_DIR/plan.md"

      echo "plan.md OK"


  - id: approve-plan
    type: gate

    message: "Review the architecture plan and continue?"

    options:
      - approve
      - reject

    on_reject: abort


  # ==========================================================
  # TESTER
  # ==========================================================

  - id: tester
    type: prompt
    integration: $TESTER_PROVIDER
$tester_model_line
    prompt: |
      Act as an independent acceptance Tester.

      Read the active feature specification and architecture plan.

      Create acceptance tests under:

        tests/acceptance/

      Rules:

      - Test externally observable behavior.
      - Do not modify production code under src/.
      - Do not modify the specification.
      - Do not modify the architecture plan.
      - Do not weaken requirements.
      - Tests should fail before implementation.


  - id: verify-tests
    type: shell

    run: |
      set -eu

      test -d tests/acceptance

      COUNT="\$(
        find tests/acceptance \
          -type f \
          -name '*.py' |
        wc -l |
        tr -d ' '
      )"

      test "\$COUNT" -gt 0

      if ! git diff --quiet -- src; then
        echo "Tester modified tracked production code."
        exit 1
      fi

      if [ -n "\$(git ls-files --others --exclude-standard src)" ]; then
        echo "Tester created production files."
        exit 1
      fi

      uv run pytest \
        --collect-only \
        -q \
        tests/acceptance \
        >/dev/null

      echo "Acceptance tests OK"


  - id: verify-red
    type: shell

    run: |
      set -eu

      if uv run pytest -q tests/acceptance; then
        echo "Acceptance tests unexpectedly pass before implementation."
        exit 1
      fi

      echo "RED phase confirmed"


  - id: approve-tests
    type: gate

    message: "Review the independent acceptance tests and continue?"

    options:
      - approve
      - reject

    on_reject: abort


  # ==========================================================
  # PLANNER
  # ==========================================================

  - id: planner
    command: speckit.tasks
    integration: $PLANNER_PROVIDER
$planner_model_line
    input:
      args: >
        Generate the implementation task list from the
        approved specification and architecture.

        Existing acceptance tests are an approved
        behavioral contract.

        Implementation must satisfy them rather than rewrite them.


  - id: verify-tasks
    type: shell

    run: |
      set -eu

      FEATURE_DIR="specs/\$(git branch --show-current)"

      test -s "\$FEATURE_DIR/tasks.md"

      echo "tasks.md OK"


  # ==========================================================
  # ANALYSIS
  # ==========================================================

  - id: analyze
    command: speckit.analyze
    integration: $PLANNER_PROVIDER
$planner_model_line
    input:
      args: >
        Check the specification, architecture plan,
        tasks and acceptance contract for:

        - contradictions
        - ambiguity
        - missing coverage
        - inconsistent requirements

        Do not modify artifacts.


  - id: approve-implementation
    type: gate

    message: "Review analysis output. Start implementation?"

    options:
      - approve
      - reject

    on_reject: abort


  # ==========================================================
  # SNAPSHOT ACCEPTANCE CONTRACT
  # ==========================================================

  - id: snapshot-tests
    type: shell

    run: |
      set -eu

      SNAP="/tmp/speckit-{{ context.run_id }}-acceptance.sha256"

      : > "\$SNAP"

      find tests/acceptance \
        -type f \
        -name '*.py' |
      sort |
      while IFS= read -r file; do
        shasum -a 256 "\$file"
      done > "\$SNAP"

      test -s "\$SNAP"

      echo "Acceptance contract frozen"


  # ==========================================================
  # CODER
  # ==========================================================

  - id: coder
    command: speckit.implement
    integration: $CODER_PROVIDER
$coder_model_line
    input:
      args: >
        Act as the implementation Coder.

        Implement the approved tasks.

        Do not modify the approved acceptance tests
        merely to make them pass.

        Prefer the smallest maintainable implementation.

        Run formatting and relevant tests before finishing.


  - id: verify-test-contract
    type: shell

    run: |
      set -eu

      SNAP="/tmp/speckit-{{ context.run_id }}-acceptance.sha256"

      shasum -a 256 -c "\$SNAP"

      echo "Acceptance contract unchanged"


  # ==========================================================
  # CI
  # ==========================================================

  - id: ci
    type: shell

    run: |
      set -eu

      make ci


  # ==========================================================
  # CONVERGENCE
  # ==========================================================

  - id: converge
    command: speckit.converge
    integration: $REVIEWER_PROVIDER
$reviewer_model_line
    input:
      args: >
        Compare the implementation with:

        - specification
        - architecture plan
        - task list
        - acceptance contract

        Append tasks only for genuine remaining
        implementation gaps.


  - id: verify-converged
    type: shell

    run: |
      set -eu

      FEATURE_DIR="specs/\$(git branch --show-current)"

      if grep -F -n -- "- [ ]" "\$FEATURE_DIR/tasks.md"; then
        echo "Unfinished tasks remain."
        exit 1
      fi

      echo "Convergence OK"


  # ==========================================================
  # REVIEWER
  # ==========================================================

  - id: reviewer
    type: prompt
    integration: $REVIEWER_PROVIDER
$reviewer_model_line
    prompt: |
      Act as an independent senior Reviewer.

      Review:

      - specification
      - architecture plan
      - implementation tasks
      - acceptance tests
      - production code
      - git diff
      - CI-visible state

      Do not edit files.

      Report findings as:

      BLOCKER
      MAJOR
      MINOR
      NIT

      Finish with exactly:

      BLOCKERS_REMAIN: yes|no
      MAJORS_REMAIN: yes|no


  # ==========================================================
  # FINAL GATE
  # ==========================================================

  - id: final-approval
    type: gate

    message: "Review final report and diff. Accept implementation?"

    options:
      - approve
      - reject

    on_reject: abort
EOF

  ok "Created workflows/agent-track.yml"
}


# ------------------------------------------------------------
# README
# ------------------------------------------------------------

write_readme() {
  cat > README.md <<EOF
# $PROJECT_NAME

Bootstrapped agentic Python project.

## Stack

- Python 3.12
- uv
- pytest
- Ruff
- mypy
- pre-commit
- GitHub Actions
- GitHub Spec Kit
- Claude Code
- OpenAI Codex
- OpenCode
- optional LM Studio models

## Agent routing

See:

\`\`\`
.agentic/providers.json
\`\`\`

## Workflow

Interactive requirements phase first.

Use your configured Analyst integration and run:

\`\`\`
speckit.specify
speckit.clarify
\`\`\`

The exact invocation syntax depends on the integration.

Examples:

Claude:

\`\`\`
/speckit.specify
/speckit.clarify
\`\`\`

Codex:

\`\`\`
\$speckit-specify
\$speckit-clarify
\`\`\`

Then commit the approved specification and run:

\`\`\`bash
specify workflow run ./workflows/agent-track.yml
\`\`\`

## CI

\`\`\`bash
make ci
\`\`\`

## Shared agent configs

Claude:

\`\`\`
.claude/settings.json
\`\`\`

Codex:

\`\`\`
.codex/config.toml
\`\`\`

OpenCode:

\`\`\`
opencode.jsonc
\`\`\`

## Machine-local trust

Codex project trust is stored under:

\`\`\`
~/.codex/config.toml
\`\`\`

Claude project trust/onboarding is intentionally completed through
the Claude CLI on each machine rather than committed to the repository.
EOF
}


# ------------------------------------------------------------
# SUMMARY
# ------------------------------------------------------------

print_routing() {
  echo
  printf "${BOLD}Selected routing${RESET}\n"
  echo

  printf "%-12s %-12s %s\n" "Role" "Provider" "Model"
  printf "%-12s %-12s %s\n" "------------" "------------" "------------------------------"

  printf "%-12s %-12s %s\n" \
    "Analyst" \
    "$ANALYST_PROVIDER" \
    "${ANALYST_MODEL:-<default>}"

  printf "%-12s %-12s %s\n" \
    "Architect" \
    "$ARCHITECT_PROVIDER" \
    "${ARCHITECT_MODEL:-<default>}"

  printf "%-12s %-12s %s\n" \
    "Tester" \
    "$TESTER_PROVIDER" \
    "${TESTER_MODEL:-<default>}"

  printf "%-12s %-12s %s\n" \
    "Planner" \
    "$PLANNER_PROVIDER" \
    "${PLANNER_MODEL:-<default>}"

  printf "%-12s %-12s %s\n" \
    "Coder" \
    "$CODER_PROVIDER" \
    "${CODER_MODEL:-<default>}"

  printf "%-12s %-12s %s\n" \
    "Reviewer" \
    "$REVIEWER_PROVIDER" \
    "${REVIEWER_MODEL:-<default>}"

  echo
}


# ------------------------------------------------------------
# MAIN
# ------------------------------------------------------------

main() {
  clear || true

  printf "${BOLD}"
  cat <<'EOF'

     Agentic Project Bootstrap
     =========================

     Spec Kit + Claude + Codex + OpenCode

EOF
  printf "${RESET}"

  install_base_tools
  install_agent_tools

  printf "\n${BOLD}Project${RESET}\n\n"

  PROJECT_NAME="${1:-$(ask "Project name" "my-agentic-project")}"
  PROJECT_PARENT="$(ask "Parent directory" "$HOME/Projects")"

  PROJECT_DIR="$PROJECT_PARENT/$PROJECT_NAME"

  if [[ -e "$PROJECT_DIR" ]] &&
    [[ -n "$(ls -A "$PROJECT_DIR" 2>/dev/null || true)" ]]; then
    die "Directory exists and is not empty: $PROJECT_DIR"
  fi

  mkdir -p "$PROJECT_DIR"
  cd "$PROJECT_DIR"

  PROJECT_DIR="$(pwd -P)"

  info "Creating Git repository"
  git init -b main

  info "Initializing Python project"
  uv init --package --python 3.12 .

  uv add --dev \
    pytest \
    pytest-cov \
    ruff \
    mypy \
    pre-commit

  mkdir -p \
    tests/unit \
    tests/acceptance \
    workflows \
    .agentic

  cat > tests/unit/test_smoke.py <<'EOF'
def test_smoke() -> None:
    assert True
EOF

  echo
  printf "${BOLD}Provider defaults${RESET}\n"

  REASONER_DEFAULT="$(first_available_reasoner)"
  CODER_DEFAULT="$(first_available_coder)"

  echo
  echo "Suggested defaults:"
  echo
  echo "  reasoning roles → $REASONER_DEFAULT"
  echo "  coder          → $CODER_DEFAULT"

  ANALYST_PROVIDER="$(
    choose_provider \
      "Analyst" \
      "$REASONER_DEFAULT"
  )"

  ARCHITECT_PROVIDER="$(
    choose_provider \
      "Architect" \
      "$REASONER_DEFAULT"
  )"

  TESTER_PROVIDER="$(
    choose_provider \
      "Tester" \
      "$REASONER_DEFAULT"
  )"

  PLANNER_PROVIDER="$(
    choose_provider \
      "Planner" \
      "$REASONER_DEFAULT"
  )"

  CODER_PROVIDER="$(
    choose_provider \
      "Coder" \
      "$CODER_DEFAULT"
  )"

  REVIEWER_PROVIDER="$(
    choose_provider \
      "Reviewer" \
      "$REASONER_DEFAULT"
  )"

  printf "\n${BOLD}Models${RESET}\n"

  ANALYST_MODEL="$(
    choose_model \
      "Analyst" \
      "$ANALYST_PROVIDER"
  )"

  ARCHITECT_MODEL="$(
    choose_model \
      "Architect" \
      "$ARCHITECT_PROVIDER"
  )"

  TESTER_MODEL="$(
    choose_model \
      "Tester" \
      "$TESTER_PROVIDER"
  )"

  PLANNER_MODEL="$(
    choose_model \
      "Planner" \
      "$PLANNER_PROVIDER"
  )"

  CODER_MODEL="$(
    choose_model \
      "Coder" \
      "$CODER_PROVIDER"
  )"

  REVIEWER_MODEL="$(
    choose_model \
      "Reviewer" \
      "$REVIEWER_PROVIDER"
  )"

  print_routing

  if ! confirm "Continue with this routing?" "y"; then
    die "Cancelled"
  fi

  install_spec_integrations

  if role_uses_provider claude; then
    write_claude_config
  fi

  if role_uses_provider codex; then
    write_codex_config
  fi

  if role_uses_provider opencode; then
    OPENCODE_DEFAULT_MODEL="$CODER_MODEL"

    if [[ "$CODER_PROVIDER" != "opencode" ]]; then
      if [[ "$ANALYST_PROVIDER" == "opencode" ]]; then
        OPENCODE_DEFAULT_MODEL="$ANALYST_MODEL"
      elif [[ "$ARCHITECT_PROVIDER" == "opencode" ]]; then
        OPENCODE_DEFAULT_MODEL="$ARCHITECT_MODEL"
      elif [[ "$TESTER_PROVIDER" == "opencode" ]]; then
        OPENCODE_DEFAULT_MODEL="$TESTER_MODEL"
      elif [[ "$PLANNER_PROVIDER" == "opencode" ]]; then
        OPENCODE_DEFAULT_MODEL="$PLANNER_MODEL"
      elif [[ "$REVIEWER_PROVIDER" == "opencode" ]]; then
        OPENCODE_DEFAULT_MODEL="$REVIEWER_MODEL"
      fi
    fi

    write_opencode_config "$OPENCODE_DEFAULT_MODEL"
  fi

  write_provider_manifest
  write_makefile
  append_pyproject_config
  write_precommit
  write_gitignore
  write_ci
  write_agent_workflow
  write_readme

  info "Installing pre-commit hooks"
  uv run pre-commit install

  info "Formatting project"
  make format

  info "Running baseline CI"
  make ci

  echo
  printf "${BOLD}Local machine trust${RESET}\n"

  if role_uses_provider codex; then
    configure_codex_trust "$PROJECT_DIR"
    verify_codex_trust "$PROJECT_DIR" || true
  fi

  if role_uses_provider claude; then
    configure_claude_trust "$PROJECT_DIR"
  fi

  info "Creating baseline commit"

  git add .
  git commit -m "chore: bootstrap agentic project"

  echo
  printf "${GREEN}${BOLD}Bootstrap complete${RESET}\n"
  echo

  echo "Project:"
  echo "  $PROJECT_DIR"
  echo

  echo "Routing:"
  echo "  .agentic/providers.json"
  echo

  echo "Workflow:"
  echo "  workflows/agent-track.yml"
  echo

  echo "Run:"
  echo
  echo "  cd \"$PROJECT_DIR\""
  echo

  case "$ANALYST_PROVIDER" in
    claude)
      if [[ -n "$ANALYST_MODEL" ]]; then
        echo "  claude --model \"$ANALYST_MODEL\""
      else
        echo "  claude"
      fi
      ;;

    codex)
      if [[ -n "$ANALYST_MODEL" ]]; then
        echo "  codex -m \"$ANALYST_MODEL\""
      else
        echo "  codex"
      fi
      ;;

    opencode)
      if [[ -n "$ANALYST_MODEL" ]]; then
        echo "  opencode --model \"$ANALYST_MODEL\""
      else
        echo "  opencode"
      fi
      ;;
  esac

  echo
  echo "Create and clarify the spec, commit it, then:"
  echo
  echo "  specify workflow validate ./workflows/agent-track.yml"
  echo "  specify workflow run ./workflows/agent-track.yml"
  echo

  if have gh && gh auth status >/dev/null 2>&1; then
    if confirm "Create GitHub repository '$PROJECT_NAME' now?" "n"; then
      local visibility

      visibility="$(ask "Visibility: private/public" "private")"

      case "$visibility" in
        private|public)
          ;;
        *)
          die "Visibility must be private or public"
          ;;
      esac

      gh repo create "$PROJECT_NAME" \
        "--$visibility" \
        --source=. \
        --remote=origin \
        --push

      ok "GitHub repository created"
    fi
  else
    warn "GitHub CLI is not authenticated"
    echo
    echo "Run:"
    echo
    echo "  gh auth login"
  fi
}


main "$@"
