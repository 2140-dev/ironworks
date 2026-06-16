#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: run-correctness [SOURCE_PATH]

Build the local correctness stage against SOURCE_PATH. If SOURCE_PATH is
omitted, ../2140-node is used.
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

source_path="${1:-../2140-node}"
if [[ ! -d "$source_path" ]]; then
  echo "Source path does not exist: $source_path" >&2
  exit 1
fi

source_path="$(cd "$source_path" && pwd)"
system="$(nix eval --raw --expr builtins.currentSystem)"

exec nix build ".#checks.${system}.correctness" \
  --override-input node "path:${source_path}" \
  --print-build-logs
