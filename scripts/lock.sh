#!/usr/bin/env bash
# Record provider hashes for both CI (linux) and local (macOS) platforms, so the
# committed .terraform.lock.hcl works in both places.
# Usage: scripts/lock.sh <root>     e.g. scripts/lock.sh stacks/static-site/dev
set -euo pipefail
source "$(dirname "$0")/lib.sh"

ROOT="${1:?usage: scripts/lock.sh <root>}"
cd "$REPO_ROOT/$ROOT"

terraform providers lock -platform=linux_amd64 -platform=darwin_arm64
ok "locked $ROOT for linux_amd64 + darwin_arm64"
