#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
exec "$script_dir/../../organize-meta-issues/scripts/summarize-meta-structure.sh" "$@"