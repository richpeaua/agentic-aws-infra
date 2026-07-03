#!/usr/bin/env bash
# List stack roots as a JSON array (for a CI matrix).
# Usage:
#   scripts/stack-roots.sh                 all stack roots that have a backend.tf
#   scripts/stack-roots.sh <base-ref>      only roots affected by changes vs <base-ref>
# A root is "affected" if files under it, or under its module (modules/<name>), changed.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
cd "$REPO_ROOT"

all_roots() {
  find stacks -type f -name backend.tf 2>/dev/null | while read -r f; do dirname "$f"; done | sort -u
}

to_json() {
  python3 -c 'import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))'
}

if [ "${1:-}" = "" ]; then
  all_roots | to_json
  exit 0
fi

base="$1"
changed="$(git diff --name-only "${base}...HEAD" 2>/dev/null || true)"
[ -z "$changed" ] && changed="$(git diff --name-only "${base}" 2>/dev/null || true)"

{
  while read -r root; do
    [ -z "$root" ] && continue
    name="$(printf '%s' "$root" | cut -d/ -f2)"
    if printf '%s\n' "$changed" | grep -qE "^(${root}/|stacks/${name}/|modules/${name}/)"; then
      printf '%s\n' "$root"
    fi
  done < <(all_roots)
} | sort -u | to_json
