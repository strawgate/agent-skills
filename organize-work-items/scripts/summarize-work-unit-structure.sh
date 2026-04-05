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

python3 - "$issues_file" "$out_dir/work-units.json" "$out_dir/work-unit-links.tsv" "$out_dir/unassigned-open-issues.json" "$out_dir/work-unit-summary.md" <<'PY'
import json
import re
import sys

issues_path, work_units_path, links_path, unassigned_path, summary_path = sys.argv[1:6]

with open(issues_path) as fh:
    raw_issues = json.load(fh)

child_ref_pattern = re.compile(r'(?:- \[[ xX]\]\s*#(\d+))|(?:\|\s*#(\d+)\s*\|)|(?:#(\d+))')

def label_names(issue):
    names = []
    for label in issue.get('labels') or []:
        if isinstance(label, str):
            names.append(label)
        elif isinstance(label, dict):
            names.append(label.get('name', ''))
    return names

def child_refs(body):
    seen = []
    for match in child_ref_pattern.finditer(body or ''):
        child = next((group for group in match.groups() if group), None)
        if child is None:
            continue
        child_num = int(child)
        if child_num not in seen:
            seen.append(child_num)
    return seen

def is_work_unit(issue):
    title = (issue.get('title') or '').strip().lower()
    labels = {name.lower() for name in label_names(issue)}
    if 'work-unit' in labels:
        return True
    if title.startswith('work-unit:'):
        return True
    return False

def is_meta_like(issue):
    title = (issue.get('title') or '').strip().lower()
    return title.startswith(('meta:', 'phase:', 'epic:', 'work-unit:'))

issues = []
for issue in raw_issues:
    issues.append({
        'number': issue['number'],
        'title': issue.get('title') or '',
        'body': issue.get('body') or '',
        'labels': label_names(issue),
        'html_url': issue.get('html_url') or '',
    })

work_units = [issue for issue in issues if is_work_unit(issue)]
link_map = {issue['number']: child_refs(issue['body']) for issue in work_units}
scheduled_children = {child for refs in link_map.values() for child in refs if child != 0}

unassigned = []
for issue in issues:
    if is_meta_like(issue):
        continue
    if issue['number'] in scheduled_children:
        continue
    unassigned.append({
        'number': issue['number'],
        'title': issue['title'],
        'labels': issue['labels'],
        'html_url': issue['html_url'],
    })

with open(work_units_path, 'w') as fh:
    json.dump(work_units, fh, indent=2)

with open(links_path, 'w') as fh:
    fh.write('work_unit\tchild\n')
    for parent in sorted(link_map):
        for child in link_map[parent]:
            fh.write(f'{parent}\t{child}\n')

with open(unassigned_path, 'w') as fh:
    json.dump(unassigned, fh, indent=2)

lines = []
lines.append('# Work Unit Structure Summary')
lines.append('')
lines.append(f'- open_work_units: {len(work_units)}')
lines.append(f'- unassigned_open_leaf_issues: {len(unassigned)}')
lines.append('')
lines.append('## Existing work units')
lines.append('')
for issue in sorted(work_units, key=lambda item: item['number']):
    labels = ', '.join(issue.get('labels') or [])
    children = ', '.join(f'#{num}' for num in link_map.get(issue['number'], [])) or '(none found)'
    lines.append(f"- #{issue['number']} {issue['title']}")
    lines.append(f"  labels: {labels or '(none)'}")
    lines.append(f"  linked items: {children}")
lines.append('')
lines.append('## Open issues not scheduled in a work unit')
lines.append('')
for issue in sorted(unassigned, key=lambda item: item['number']):
    labels = ', '.join(issue.get('labels') or [])
    lines.append(f"- #{issue['number']} {issue['title']} [{labels or 'no-labels'}]")

with open(summary_path, 'w') as fh:
    fh.write('\n'.join(lines) + '\n')
PY

echo "$out_dir/work-unit-summary.md"