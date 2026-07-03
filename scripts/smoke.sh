#!/usr/bin/env bash
# Post-apply smoke test for a deployed root. Best-effort and generic:
# if the root exposes a `website_endpoint` output, verify it serves HTTP 200.
# Phase 8 expands this into per-stack tests under tests/.
# Usage: scripts/smoke.sh <root>   (run after terraform apply, in an initialized root)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

ROOT="${1:?usage: scripts/smoke.sh <root>}"
cd "$REPO_ROOT"

endpoint="$(terraform -chdir="$ROOT" output -raw website_endpoint 2>/dev/null || true)"

if [ -z "$endpoint" ]; then
  ok "no website_endpoint output in $ROOT; nothing to smoke test"
  exit 0
fi

log "smoke test: $endpoint"
if curl -fsS --retry 5 --retry-delay 3 "$endpoint" >/dev/null; then
  ok "smoke passed: $endpoint returns 200"
else
  die "smoke failed: $endpoint did not return success"
fi
