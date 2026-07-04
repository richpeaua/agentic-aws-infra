#!/usr/bin/env bash
# Inspect and prune the local headless-agent run store (.agents/runs/).
#
# Usage:
#   scripts/runs.sh list [--children] [--json]     list parent runs (add reviewer children / JSON)
#   scripts/runs.sh show <run-id>                  metadata + artifact paths for one run
#   scripts/runs.sh clean --older-than <Nd> [--dry-run]   remove run dirs older than N days
#
# Records are local and git-ignored; they may contain sensitive prompts and tool output.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
source "$REPO_ROOT/scripts/lib/telemetry.sh"

RUNS_DIR="$(telemetry_runs_dir)"

usage() {
  sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//' >&2
  exit 2
}

# Emit metadata.json paths for existing runs, newest first (ids sort chronologically).
_run_metas() {
  [ -d "$RUNS_DIR" ] || return 0
  find "$RUNS_DIR" -mindepth 2 -maxdepth 2 -name metadata.json 2>/dev/null | sort -r
}

_fmt_duration() {
  case "$1" in
    ''|null) printf -- '-' ;;
    *)       printf '%ss' "$1" ;;
  esac
}

cmd_list() {
  local children=0 json=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --children) children=1; shift ;;
      --json)     json=1; shift ;;
      *) die "unknown argument: $1" ;;
    esac
  done

  # Select metadata files, dropping reviewer children unless --children.
  local metas=() m kind
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    kind="$(jq -r '.kind // ""' "$m" 2>/dev/null || echo "")"
    if [ "$children" -eq 0 ] && [ "$kind" = "review-child" ]; then continue; fi
    metas+=("$m")
  done < <(_run_metas)

  if [ "$json" -eq 1 ]; then
    if [ "${#metas[@]}" -eq 0 ]; then printf '[]\n'; return 0; fi
    jq -s '.' "${metas[@]}"
    return 0
  fi

  if [ "${#metas[@]}" -eq 0 ]; then
    log "no runs recorded under .agents/runs/"
    return 0
  fi

  printf '%-34s %-13s %-22s %-8s %-14s %-9s %s\n' \
    "RUN ID" "KIND" "AGENT" "PROVIDER" "STATUS" "DURATION" "ISSUE"
  for m in "${metas[@]}"; do
    # One tab-separated row per run via jq, then formatted.
    IFS=$'\t' read -r rid kind agent prov status dur issue < <(
      jq -r '[.run_id, .kind, .agent, .provider, .status,
              (.duration_seconds|tostring), (.issue // "-")] | @tsv' "$m" 2>/dev/null
    ) || continue
    printf '%-34s %-13s %-22s %-8s %-14s %-9s %s\n' \
      "$rid" "$kind" "$agent" "$prov" "$status" "$(_fmt_duration "$dur")" "$issue"
  done
}

cmd_show() {
  local id="${1:?usage: scripts/runs.sh show <run-id>}"
  local dir="$RUNS_DIR/$id"
  [ -d "$dir" ] || die "no such run: $id"
  local meta="$dir/metadata.json"

  log "run $id"
  if [ -f "$meta" ]; then jq '.' "$meta"; else warn "no metadata.json"; fi

  echo
  log "artifacts"
  find "$dir" -type f 2>/dev/null | sort | sed "s#^$REPO_ROOT/#  #"

  # Reviewer child runs link back via .parent; surface them for review parents.
  local kids
  kids="$(_run_metas | while IFS= read -r m; do
    [ "$(jq -r '.parent // ""' "$m" 2>/dev/null)" = "$id" ] && jq -r '.run_id' "$m" 2>/dev/null
  done)"
  if [ -n "$kids" ]; then
    echo
    log "child runs"
    printf '%s\n' "$kids" | sed 's/^/  /'
  fi
}

cmd_clean() {
  local spec="" dry=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --older-than) spec="${2:?--older-than needs a value like 30d}"; shift 2 ;;
      --dry-run)    dry=1; shift ;;
      *) die "unknown argument: $1" ;;
    esac
  done
  [ -n "$spec" ] || die "clean requires --older-than <Nd> (e.g. 30d)"
  case "$spec" in
    *d) : ;;
    *)  die "unsupported age '$spec'; use days, e.g. 30d" ;;
  esac
  local days="${spec%d}"
  case "$days" in ''|*[!0-9]*) die "invalid day count in '$spec'" ;; esac

  [ -d "$RUNS_DIR" ] || { log "nothing to clean (.agents/runs/ absent)"; return 0; }
  local now cutoff removed=0
  now="$(date -u +%s)"
  cutoff=$(( now - days * 86400 ))

  local m dir epoch
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    dir="$(dirname "$m")"
    epoch="$(jq -r '.start_epoch // empty' "$m" 2>/dev/null || true)"
    # Fall back to directory mtime when start_epoch is absent.
    if [ -z "$epoch" ]; then
      epoch="$(_mtime "$dir")"
    fi
    if [ -n "$epoch" ] && [ "$epoch" -lt "$cutoff" ]; then
      if [ "$dry" -eq 1 ]; then
        printf 'would remove %s\n' "$(basename "$dir")"
      else
        rm -rf "$dir" && ok "removed $(basename "$dir")"
      fi
      removed=$(( removed + 1 ))
    fi
  done < <(_run_metas)
  log "clean complete: $removed run(s) older than ${days}d $( [ "$dry" -eq 1 ] && echo '(dry-run)')"
}

# Portable directory mtime as epoch (GNU stat vs BSD/macOS stat).
_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo ""
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    list)  cmd_list "$@" ;;
    show)  cmd_show "$@" ;;
    clean) cmd_clean "$@" ;;
    ''|-h|--help) usage ;;
    *) die "unknown command: $sub (expected list|show|clean)" ;;
  esac
}
main "$@"
