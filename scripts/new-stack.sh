#!/usr/bin/env bash
# Scaffold a new stack: a reusable module plus dev and prod roots, from the
# canonical template. Every stack ends up structurally identical.
# Usage: scripts/new-stack.sh <name>     name = lowercase letters, digits, dashes
set -euo pipefail
source "$(dirname "$0")/lib.sh"

NAME="${1:?usage: scripts/new-stack.sh <name>}"
printf '%s' "$NAME" | grep -qE '^[a-z][a-z0-9-]*$' || die "name must be lowercase letters, digits, and dashes (got '$NAME')"

MOD="$REPO_ROOT/modules/$NAME"
STACK="$REPO_ROOT/stacks/$NAME"
TPL="$REPO_ROOT/templates/stack"

[ -e "$MOD" ]   && die "modules/$NAME already exists"
[ -e "$STACK" ] && die "stacks/$NAME already exists"
[ -d "$TPL" ]   || die "template missing at templates/stack"

export RENDER_STACK="$NAME"
export RENDER_PROJECT="aws-agentic-infra"

# Module
mkdir -p "$MOD"
export RENDER_ENV=""
for f in "$TPL/module"/*; do
  render "$f" "$MOD/$(basename "$f")"
done
ok "modules/$NAME"

# Per-environment roots
for env in dev prod; do
  DEST="$STACK/$env"
  mkdir -p "$DEST"
  export RENDER_ENV="$env"
  for f in "$TPL/env"/*; do
    render "$f" "$DEST/$(basename "$f")"
  done
  cp "$REPO_ROOT/backend.tfbackend.example" "$DEST/backend.tfbackend.example"
  ok "stacks/$NAME/$env"
done

cat <<EOF

Scaffolded stack '$NAME'. Next:
  1. Define resources in modules/$NAME/main.tf and outputs in modules/$NAME/outputs.tf.
  2. In each of stacks/$NAME/{dev,prod}: cp backend.tfbackend.example backend.tfbackend and set the bucket.
  3. Validate:  scripts/check.sh stacks/$NAME/dev
  4. Plan:      scripts/plan.sh  stacks/$NAME/dev
  5. Run the review panel, then open a PR. Do not apply locally.
EOF
