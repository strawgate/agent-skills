#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 OWNER/REPO [OUT_DIR]" >&2
  exit 1
fi

repo="$1"
out_dir="${2:-/tmp/issue-organizer/${repo//\//__}}"
issues_file="$out_dir/open-issues.json"

if [[ ! -f "$issues_file" ]]; then
  "$(dirname "$0")/fetch-repo-data.sh" "$repo" "$out_dir" >/dev/null
fi

python3 - "$issues_file" "$out_dir/meta-issues.json" "$out_dir/child-links.tsv" "$out_dir/orphan-open-issues.json" "$out_dir/meta-summary.md" <<'PY'
import json
import re
import sys
from collections import defaultdict

issues_path, meta_path, links_path, orphan_path, summary_path = sys.argv[1:6]

with open(issues_path) as fh:
  raw_issues = json.load(fh)

child_ref_pattern = re.compile(r'(?:- \[[ xX]\]\s*#(\d+))|(?:\|\s*#(\d+)\s*\|)')
section_pattern = re.compile(r'##\s+(Child issues|Sub-issues|Implementation phases|Phases)\b', re.IGNORECASE)

def label_names(issue):
  return [label.get('name', '') for label in issue.get('labels') or []]

def child_refs(body):
  seen = []
  for match in child_ref_pattern.finditer(body or ''):
    child = next(group for group in match.groups() if group)
    if child not in seen:
      seen.append(child)
  return seen

def is_meta(issue):
  title = (issue.get('title') or '').strip().lower()
  body = issue.get('body') or ''
  if title.startswith(('meta:', 'epic:', 'phase:')):
    return True
  if section_pattern.search(body):
    return True
  return False

issues = []
for issue in raw_issues:
  issues.append({
    'number': issue['number'],
    'title': issue.get('title') or '',
    'body': issue.get('body') or '',
    'labels': label_names(issue),
    'assignees': issue.get('assignees') or [],
    'html_url': issue.get('html_url') or '',
  })

metas = [issue for issue in issues if is_meta(issue)]
child_map = {issue['number']: [int(child) for child in child_refs(issue['body'])] for issue in metas}
children = {child for refs in child_map.values() for child in refs}

orphans = []
for issue in issues:
  if is_meta(issue):
    continue
  if issue['number'] in children:
    continue
  orphans.append({
    'number': issue['number'],
    'title': issue['title'],
    'labels': issue['labels'],
    'html_url': issue['html_url'],
  })

with open(meta_path, 'w') as fh:
  json.dump(metas, fh, indent=2)

with open(links_path, 'w') as fh:
  fh.write('parent\tchild\n')
  for parent in sorted(child_map):
    for child in child_map[parent]:
      fh.write(f'{parent}\t{child}\n')

with open(orphan_path, 'w') as fh:
  json.dump(orphans, fh, indent=2)

lines = []
lines.append('# Meta Structure Summary')
lines.append('')
lines.append(f'- meta_like_open_issues: {len(metas)}')
lines.append(f'- orphan_open_issues: {len(orphans)}')
lines.append('')
lines.append('## Existing metas')
lines.append('')
for issue in sorted(metas, key=lambda item: item['number']):
  labels = ', '.join(issue.get('labels') or [])
  child_list = ', '.join(f'#{num}' for num in child_map.get(issue['number'], [])) or '(none found)'
  lines.append(f"- #{issue['number']} {issue['title']}")
  lines.append(f"  labels: {labels or '(none)'}")
  lines.append(f"  children: {child_list}")
lines.append('')
lines.append('## Orphans')
lines.append('')
for issue in sorted(orphans, key=lambda item: item['number']):
  labels = ', '.join(issue.get('labels') or [])
  lines.append(f"- #{issue['number']} {issue['title']} [{labels or 'no-labels'}]")

with open(summary_path, 'w') as fh:
  fh.write('\n'.join(lines) + '\n')
PY

echo "$out_dir/meta-summary.md"