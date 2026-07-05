#!/usr/bin/env bash
# Regenerate the terraform-docs inputs/outputs table in each module's README.
#
# Each module under modules/<name>/ has a README with a hand-written purpose
# paragraph and a terraform-docs BEGIN_TF_DOCS/END_TF_DOCS marker pair; this
# script injects the generated inputs/outputs table between those markers.
#
# Usage:
#   scripts/gen-docs.sh            rewrite the tables in place
#   scripts/gen-docs.sh --check    fail (non-zero) if any table is out of date,
#                                   without modifying files. Used by CI.
#
# Deterministic and non-interactive; the table content is a pure function of the
# module's .tf and the pinned terraform-docs version (see README prerequisites).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

CHECK=0
case "${1:-}" in
  --check) CHECK=1 ;;
  "") ;;
  *) die "usage: scripts/gen-docs.sh [--check]" ;;
esac

has terraform-docs || die "terraform-docs not installed (see the README prerequisites)"

args=(markdown table --output-file README.md --output-mode inject)
[ "$CHECK" -eq 1 ] && args+=(--output-check)

status=0
found=0
for dir in "$REPO_ROOT"/modules/*/; do
  # Only real module directories (those containing Terraform).
  ls "$dir"*.tf >/dev/null 2>&1 || continue
  found=1
  name="$(basename "$dir")"
  if [ ! -f "$dir/README.md" ]; then
    die "missing $dir/README.md; create it with a purpose paragraph and the BEGIN_TF_DOCS/END_TF_DOCS markers (see modules/README.md)"
  fi
  if terraform-docs "${args[@]}" "$dir" >/dev/null; then
    [ "$CHECK" -eq 1 ] && ok "$name docs up to date" || ok "$name docs regenerated"
  else
    status=1
    if [ "$CHECK" -eq 1 ]; then
      warn "$name docs are out of date; run scripts/gen-docs.sh and commit modules/$name/README.md"
    else
      warn "$name docs generation failed"
    fi
  fi
done

[ "$found" -eq 1 ] || die "no modules with Terraform found under modules/"
exit "$status"
