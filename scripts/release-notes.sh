#!/bin/bash
# Print the CHANGELOG.md body for MARKETING_VERSION (no heading).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/version.env"

notes="$(
  awk -v ver="$MARKETING_VERSION" '
    $0 ~ "^## " ver { grab = 1; next }
    grab && /^## / { exit }
    grab { print }
  ' "$ROOT/CHANGELOG.md"
)"
notes="$(printf '%s\n' "$notes" | sed -e :a -e '/^\n*$/{$d;N;ba' -e '}')"

if [[ -z "${notes//[$' \t\n']/}" ]]; then
  echo "CHANGELOG.md has no section for ${MARKETING_VERSION}" >&2
  exit 1
fi

printf '%s\n' "$notes"
