#!/usr/bin/env bash
# Verify the local environment is ready to work. Read-only; safe to run anytime.
# Usage: scripts/preflight.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

rc=0

log "Preflight checks"

if aws sts get-caller-identity >/dev/null 2>&1; then
  ok "AWS identity: account $(aws sts get-caller-identity --query Account --output text)"
else
  warn "AWS credentials not valid. Run: aws sso login --profile ${AWS_PROFILE}"
  rc=1
fi

if has terraform; then
  ok "$(terraform version | head -1)"
else
  warn "terraform not installed"
  rc=1
fi

for t in gh jq; do
  if has "$t"; then
    ok "$t present"
  else
    warn "$t not installed"
    rc=1
  fi
done

# Gate tools. Missing ones are warnings, not failures, because some are added in later phases.
for t in tflint checkov conftest infracost; do
  if has "$t"; then ok "$t present"; else warn "$t not installed (needed by the gate stack)"; fi
done

if [ "$rc" -eq 0 ]; then log "Preflight OK"; else warn "Preflight found issues above"; fi
exit "$rc"
