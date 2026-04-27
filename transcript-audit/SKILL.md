# Transcript Audit Skill

Use real agent conversations to discover skill gaps and propose improvements.

## Concept

An agent reviews actual transcripts from various AI coding tools (OpenCode, Claude, Copilot, Codex, Cline) to identify:
1. What users actually ask for vs what skills provide
2. Missing capabilities that users repeatedly need
3. Confusion points and failure patterns
4. Specific improvements to skills and prompts

## Transcript Sources

| Agent | Path | Format |
|-------|------|--------|
| OpenCode | `~/.claude/history.jsonl` | JSONL - user prompts with project context |
| Cline/Copilot | `~/Library/Application Support/Cursor/User/globalStorage/rooveterinaryinc.roo-cline/tasks/*/api_conversation_history.json` | JSON - multi-turn conversations |
| Claude Desktop | `~/.claude/sessions/*.json` | JSON - session metadata |
| Codex | `~/.codex/` | Various logs and sessions |

## Your Task

When you run this skill:

1. **Find transcripts**: Use the scripts below to locate and extract relevant conversations
2. **Read samples**: Pull actual user prompts and agent responses from each source
3. **Analyze patterns**:
   - What tasks do users repeatedly request?
   - Where do agents fail or confusion arises?
   - What context do users provide vs what skills assume?
   - Which skills are mentioned and how are they used?
4. **Propose improvements**: Based on real usage, suggest specific changes to SKILL.md files

## Scripts

### find-transcripts.sh
Locate all transcript files on the system:
```bash
~/.claude/skills/transcript-audit/scripts/find-transcripts.sh
```

### extract-opencode.py <output_dir>
Extract recent OpenCode prompts to a directory:
```bash
uv run python ~/.claude/skills/transcript-audit/scripts/extract-opencode.py /tmp/transcripts/opencode
```

### extract-cline.py <output_dir>
Extract Cline/Copilot conversations:
```bash
uv run python ~/.claude/skills/transcript-audit/scripts/extract-cline.py /tmp/transcripts/cline
```

### sample-transcripts.py <source> <count>
Get random sample of transcripts for analysis:
```bash
uv run python ~/.claude/skills/transcript-audit/scripts/sample-transcripts.py opencode 20
uv run python ~/.claude/skills/transcript-audit/scripts/sample-transcripts.py cline 10
```

## Analysis Framework

When reviewing transcripts, look for:

**Task Patterns**
- What categories of tasks appear most often?
- What is the ratio of research vs implementation vs debugging?

**Context Patterns**
- How much context do users provide upfront?
- What context is missing that would help?

**Success/Failure Signals**
- Explicit feedback ("thanks", "perfect", "that worked")
- Implicit signals (follow-up questions, same issue repeated)

**Skill Mentions**
- Which skills are users reaching for?
- Are they using skills correctly?

## Output Format

After analysis, provide:

```
## Transcript Analysis: [source]

### Top Task Categories
- category: count, example_prompt

### Missing Capabilities
- capability: evidence_from_transcript

### Skill Gaps
- skill_name: what's needed vs what exists

### Recommended Improvements
1. [skill]: specific_change_with_rationale
```

## Important

- **Do read actual transcripts** - don't just summarize known patterns
- **Cite specific examples** - quote actual user prompts that illustrate points
- **Be actionable** - propose specific changes, not vague improvements
- **Prioritize** - focus on patterns that appear multiple times