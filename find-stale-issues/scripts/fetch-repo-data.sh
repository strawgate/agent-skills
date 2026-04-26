#!/usr/bin/env bash
# Fetch repo data and build semantic similarity indexes
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
exec "$script_dir/../../_shared/github-repo-inventory/scripts/index-repo.sh" "$@"