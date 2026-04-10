#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
exec "$script_dir/../../_shared/github-repo-inventory/scripts/fetch-repo-data.sh" "$@"
