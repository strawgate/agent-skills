#!/usr/bin/env bash
# Shared Jules API library.
# Source this file, then call the functions below.
#
# Usage in scripts:
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   source "$SCRIPT_DIR/../../_shared/jules-api/jules-lib.sh"
#
# All functions require JULES_API_KEY to be set.

JULES_BASE_URL="https://jules.googleapis.com/v1alpha"

jules_require_key() {
  if [[ -z "${JULES_API_KEY:-}" ]]; then
    echo "Error: JULES_API_KEY not set. Get your key from https://jules.google.com/settings#api" >&2
    exit 1
  fi
}

# Internal: make an authenticated GET request.
# Usage: _jules_get <path> [extra curl args...]
_jules_get() {
  local path="$1"; shift
  curl -sf \
    -H "X-Goog-Api-Key: ${JULES_API_KEY}" \
    "${JULES_BASE_URL}/${path}" "$@"
}

# Internal: make an authenticated POST request with JSON body.
# Usage: _jules_post <path> <json_body>
_jules_post() {
  local path="$1" body="$2"
  curl -sf \
    -X POST \
    -H "Content-Type: application/json" \
    -H "X-Goog-Api-Key: ${JULES_API_KEY}" \
    "${JULES_BASE_URL}/${path}" \
    -d "$body"
}

# Internal: make an authenticated DELETE request.
# Usage: _jules_delete <path>
_jules_delete() {
  local path="$1"
  curl -sf \
    -X DELETE \
    -H "X-Goog-Api-Key: ${JULES_API_KEY}" \
    "${JULES_BASE_URL}/${path}"
}

# List sessions with pagination support.
# Usage: jules_list_sessions [page_size]
# Returns full JSON response (use jq to extract .sessions).
# Supports nextPageToken-based pagination via jules_list_all_sessions.
jules_list_sessions() {
  local page_size="${1:-100}"
  _jules_get "sessions?pageSize=${page_size}"
}

# List ALL sessions across pages.
# Usage: jules_list_all_sessions [page_size]
# Returns a JSON array of all sessions.
jules_list_all_sessions() {
  local page_size="${1:-100}"
  local all_sessions="[]"
  local page_token=""

  while true; do
    local url="sessions?pageSize=${page_size}"
    [[ -n "$page_token" ]] && url="${url}&pageToken=${page_token}"

    local response
    response="$(_jules_get "$url")" || { echo "$all_sessions"; return 1; }

    local page_sessions
    page_sessions="$(jq -c '.sessions // []' <<<"$response")"
    all_sessions="$(jq -s '.[0] + .[1]' <<<"$all_sessions"$'\n'"$page_sessions")"

    page_token="$(jq -r '.nextPageToken // empty' <<<"$response")"
    [[ -z "$page_token" ]] && break
  done

  echo "$all_sessions"
}

# Get a single session's details.
# Usage: jules_get_session <session_id>
jules_get_session() {
  local session_id="$1"
  _jules_get "sessions/${session_id}"
}

# Get session state.
# Usage: jules_get_state <session_id>
jules_get_state() {
  local session_id="$1"
  jules_get_session "$session_id" | jq -r '.state // "UNKNOWN"'
}

# Get session activities.
# Usage: jules_get_activities <session_id> [page_size]
jules_get_activities() {
  local session_id="$1" page_size="${2:-20}"
  _jules_get "sessions/${session_id}/activities?pageSize=${page_size}"
}

# Send a message/prompt to a session.
# Usage: jules_send_message <session_id> <message>
jules_send_message() {
  local session_id="$1" message="$2"
  _jules_post "sessions/${session_id}:sendMessage" \
    "$(jq -n --arg msg "$message" '{prompt: $msg}')"
}

# Create a new session.
# Usage: jules_create_session <json_body>
jules_create_session() {
  local body="$1"
  _jules_post "sessions" "$body"
}

# Delete a session.
# Usage: jules_delete_session <session_id>
jules_delete_session() {
  local session_id="$1"
  _jules_delete "sessions/${session_id}" >/dev/null
}

# Extract PR URL from session detail JSON.
# Usage: jules_extract_pr_url <session_detail_json>
jules_extract_pr_url() {
  local detail="$1"
  jq -r '.outputs[]?.pullRequest?.url // empty' <<<"$detail" | head -1
}

# Portable date math: seconds since epoch from ISO 8601 timestamp.
# Usage: jules_epoch_from_iso <iso_timestamp>
jules_epoch_from_iso() {
  local ts="$1"
  python3 -c "
from datetime import datetime, timezone
ts = '${ts}'.replace('Z', '+00:00')
try:
    dt = datetime.fromisoformat(ts)
except ValueError:
    dt = datetime.strptime(ts[:19], '%Y-%m-%dT%H:%M:%S').replace(tzinfo=timezone.utc)
print(int(dt.timestamp()))
"
}
