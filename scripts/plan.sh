#!/usr/bin/env bash
# Init a root against remote state and produce a plan plus a cost estimate.
# Local helper; application applies happen only in CI.
# Usage: scripts/plan.sh <root-dir>     e.g. scripts/plan.sh stacks/static-site/dev
set -euo pipefail
source "$(dirname "$0")/lib.sh"

ROOT="${1:?usage: scripts/plan.sh <root-dir>}"
cd "$REPO_ROOT/$ROOT"

[ -f backend.tfbackend ] || die "missing backend.tfbackend in $ROOT (copy from backend.tfbackend.example and set the bucket)"

log "init: $ROOT"
terraform init -backend-config=backend.tfbackend -input=false >/dev/null
ok "init"

log "plan: $ROOT"
terraform plan -out=tfplan -input=false

if has infracost; then
  log "cost estimate"
  infracost scan . --llm || warn "infracost scan failed (check org membership / API key)"
else
  warn "infracost not installed; skipping cost estimate"
fi
