#!/usr/bin/env bash
# Fail if forbidden identifiers appear in committed/staged content.
# This is a safety net, not a guarantee. Keep the golden rule: never commit
# account IDs, bucket names, role ARNs, or real emails.
# Usage: scripts/scan-secrets.sh          (scans staged content if any, else tracked files)
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT"

# Forbidden patterns:
#   - a 12-digit AWS account ID
#   - a state bucket of the form tfstate-<account-id>
#   - an IAM ARN carrying an account ID
#   - a real email address (example.com placeholders are allowed)
PATTERNS='(\b[0-9]{12}\b)|(tfstate-[0-9]{12})|(arn:aws:[a-z0-9-]*:[a-z0-9-]*:[0-9]{12}:)|([A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,})'

# Exclusions: example templates, markdown docs (they use <placeholders>), and the
# provider lock file (contains hashes, not secrets).
PATHSPEC=(':!*.example' ':!*.md' ':!*.tfbackend' ':!.terraform.lock.hcl' ':!**/.terraform.lock.hcl')

if git diff --cached --quiet 2>/dev/null; then
  scope="tracked files"
  raw="$(git grep -nIE "$PATTERNS" -- "${PATHSPEC[@]}" 2>/dev/null || true)"
else
  scope="staged content"
  raw="$(git grep --cached -nIE "$PATTERNS" -- "${PATHSPEC[@]}" 2>/dev/null || true)"
fi

# Drop allowed placeholders (example emails, template tokens).
hits="$(printf '%s\n' "$raw" | grep -vE '@example\.|__STACK__|__ENV__|__PROJECT__|<[a-z-]+>' || true)"
hits="$(printf '%s\n' "$hits" | sed '/^$/d')"

if [ -n "$hits" ]; then
  warn "Potential secrets in ${scope}:"
  printf '%s\n' "$hits" >&2
  die "Secret scan failed. Remove the identifiers above or move them to git-ignored config."
fi

ok "Secret scan clean (${scope})"
