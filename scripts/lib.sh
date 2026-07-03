#!/usr/bin/env bash
# Shared helpers for repo scripts. Source this file; do not execute it.
# Portable across macOS (bash 3.2) and Linux (bash 5). Avoid bash-4-only features.

set -euo pipefail

# Repository root, resolved from this file's location.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Defaults; override via environment.
export AWS_PROFILE="${AWS_PROFILE:-aws-infra}"
export AWS_REGION="${AWS_REGION:-us-east-1}"

# Logging helpers (stderr for warn/die so stdout stays parseable).
log()  { printf '==> %s\n' "$*"; }
ok()   { printf '  ok  %s\n' "$*"; }
warn() { printf '  !   %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# has <cmd> -> true if the command exists.
has() { command -v "$1" >/dev/null 2>&1; }

# render <src> <dest> -> copy src to dest substituting __STACK__/__ENV__/__PROJECT__.
# Uses sed to stdout to avoid the macOS/GNU `sed -i` incompatibility.
render() {
  local src="$1" dest="$2"
  sed \
    -e "s/__STACK__/${RENDER_STACK:-}/g" \
    -e "s/__ENV__/${RENDER_ENV:-}/g" \
    -e "s/__PROJECT__/${RENDER_PROJECT:-aws-agentic-infra}/g" \
    "$src" > "$dest"
}
