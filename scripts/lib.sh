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

# run_with_timeout <seconds> <cmd> [args...]
# Run a command under a wall-clock ceiling, portably. Uses coreutils `timeout`
# or `gtimeout` when present; otherwise a bash-3.2-safe fallback that backgrounds
# the command and kills it after the deadline. A non-positive timeout means "no
# ceiling" and runs the command directly. On a timeout kill the return code is
# non-zero (124, matching coreutils), so callers can treat a tripped guard as a
# failed run. stdin/stdout/stderr are inherited, so this is safe inside a pipe.
run_with_timeout() {
  local secs="$1"; shift
  case "$secs" in ''|*[!0-9]*) secs=0 ;; esac
  if [ "$secs" -le 0 ]; then "$@"; return $?; fi
  if has timeout; then timeout "$secs" "$@"; return $?; fi
  if has gtimeout; then gtimeout "$secs" "$@"; return $?; fi
  # Portable fallback: no coreutils timeout on this host.
  "$@" &
  local pid=$!
  ( sleep "$secs"; kill -TERM "$pid" 2>/dev/null ) &
  local watcher=$!
  local rc=0
  wait "$pid" 2>/dev/null || rc=$?
  if kill -0 "$watcher" 2>/dev/null; then
    # The command finished first; cancel the still-sleeping watcher.
    kill "$watcher" 2>/dev/null || true
    wait "$watcher" 2>/dev/null || true
  else
    # The watcher already exited, so it fired the kill: this was a timeout.
    rc=124
  fi
  return "$rc"
}

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
