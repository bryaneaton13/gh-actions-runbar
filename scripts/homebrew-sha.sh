#!/bin/bash
# Print the GitHub tag tarball URL and sha256 for Formula/runbar.rb.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT/version.env"

TAG="v${MARKETING_VERSION}"
URL="https://github.com/bryaneaton13/gh-actions-runbar/archive/refs/tags/${TAG}.tar.gz"

echo "$URL"
curl -fsSL "$URL" | shasum -a 256
