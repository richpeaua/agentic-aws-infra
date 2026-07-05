#!/usr/bin/env bash
# Implementer run finalization helpers.
#
# Sourced by scripts/implement.sh (and by tests). No side effects on source.
#
# implementer_run_status <rc> <pr_url> <final_message>
#   Classify a headless implementer run from completion evidence, not from the
#   provider exit code alone. Prints one of: success | failed | incomplete.
#
#     failed      - the provider exited non-zero.
#     incomplete  - the provider exited 0 but there is no PR URL, or the final
#                   message is not meaningful (empty after trimming whitespace).
#     success     - the provider exited 0, a PR URL exists, and the final message
#                   is meaningful.
#
#   "Meaningful final message" is defined as non-empty after trimming all
#   surrounding whitespace, so a run that produced no real output is not counted
#   as success. Dry runs are classified by the caller, not here: a dry run is a
#   no-op preview and is neither success nor incomplete.
implementer_run_status() {
  local rc="$1" pr_url="$2" final_message="$3" meaningful

  if [ "$rc" -ne 0 ]; then
    printf 'failed'
    return 0
  fi

  # Strip whitespace to test for a meaningful (non-blank) final message.
  meaningful="$(printf '%s' "$final_message" | tr -d '[:space:]')"
  if [ -z "$pr_url" ] || [ -z "$meaningful" ]; then
    printf 'incomplete'
    return 0
  fi

  printf 'success'
}
