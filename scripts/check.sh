#!/usr/bin/env bash
# Run the same static checks locally that CI runs on a PR (shift-left parity).
# Usage: scripts/check.sh <root-dir>     e.g. scripts/check.sh stacks/static-site/dev
# Runs: fmt, validate, tflint, and (when configured) Checkov + Conftest.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

ROOT="${1:?usage: scripts/check.sh <root-dir>}"
cd "$REPO_ROOT/$ROOT"

log "check: $ROOT"

terraform fmt -check -recursive
ok "fmt"

terraform init -backend=false -input=false >/dev/null
terraform validate >/dev/null
ok "validate"

if has tflint && [ -f "$REPO_ROOT/.tflint.hcl" ]; then
  tflint --config "$REPO_ROOT/.tflint.hcl" >/dev/null
  ok "tflint"
else
  warn "tflint skipped (tool or .tflint.hcl missing; added in Phase 4)"
fi

# Checkov and Conftest scan the plan JSON; both arrive with Phase 4.
if has checkov && [ -f "$REPO_ROOT/policy/checkov/.checkov.yaml" ]; then
  checkov -d . --config-file "$REPO_ROOT/policy/checkov/.checkov.yaml" --compact >/dev/null
  ok "checkov"
else
  warn "checkov skipped (tool or config missing; added in Phase 4)"
fi

if has conftest && [ -d "$REPO_ROOT/policy/conftest" ]; then
  warn "conftest present but plan-based policy check runs in the pipeline (Phase 4)"
fi

log "check complete: $ROOT"
