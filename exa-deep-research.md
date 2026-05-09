# Exa Search Skill

## Overview

This skill teaches Claude how to use Exa for deep research tasks. Exa is a search API that returns clean, structured content from web pages with neural search capabilities.

## When to Use Exa

Use Exa when:
- User asks for "research", "investigate", "dig into", "what can we learn from"
- Need current information from the web (docs, news, libraries, APIs)
- Need to find real code examples, patterns, or best practices
- User wants comprehensive analysis of a topic

## Available Tools

### web_search_exa
Quick web search for factual answers or simple queries.
```
web_search_exa({
  "query": "your search query",
  "numResults": 10
})
```

### web_search_advanced_exa
Advanced search with full control over filters and options.
```
web_search_advanced_exa({
  "query": "your search query",
  "numResults": 15,
  "type": "auto", // "auto" | "fast" | "instant" (NOT "deep")
  "includeDomains": ["example.com"],
  "excludeDomains": ["example.com"],
  "startPublishedDate": "2024-01-01",
  "includeText": ["exact phrase to find"],
  "excludeText": ["phrase to exclude"],
  "enableHighlights": true,
  "highlightsMaxCharacters": 3000,
  "enableSummary": true,
  "summaryQuery": "What is the main topic?"
})
```

## Search Types

| Type | Use Case |
|------|----------|
| `auto` | General web search with quality balance (default, recommended) |
| `fast` | Quick results when speed matters |
| `instant` | Instant answers, facts |

**NOTE**: `type: "deep"` is NOT valid. Use `auto` for comprehensive research - it already provides deep search quality.

## Domain Filters

Restrict to specific domains:
```json
{
  "includeDomains": ["tanstack.com", "react.dev", "mantine.dev"]
}
```

Exclude domains:
```json
{
  "excludeDomains": ["stackoverflow.com", "github.com"]
}
```

## Query Writing Tips

### High Signal Queries
Include specific terms:
- Framework + version: "React 19", "TanStack Query v5"
- Function names: "use() hook", "queryOptions()"
- Error codes: "TS4111", "TypeScript strict mode"
- Problem descriptions: "missing key in map react"

### For Code Examples
Include language + framework:
- "Go generics" not just "generics"
- "Python async await best practices"
- "Rust error handling Option Result"

### For Documentation
Include doc type:
- "React documentation useEffect"
- "TanStack Query documentation useQuery"

## Practical Examples

### Find best practices for a library
```json
{
  "query": "TanStack Query v5 best practices useQuery 2024 2025",
  "includeDomains": ["tanstack.com"],
  "enableHighlights": true,
  "highlightsMaxCharacters": 2000
}
```

### Find recent research on a topic
```json
{
  "query": "machine learning model optimization techniques 2024 2025",
  "type": "deep",
  "startPublishedDate": "2024-01-01",
  "numResults": 20,
  "enableSummary": true
}
```

### Find API documentation
```json
{
  "query": "OpenAI API documentation streaming",
  "includeDomains": ["platform.openai.com", "api.openai.com"]
}
```

## Cloudflare Docs Tip

**Always use Markdown format** for Cloudflare docs:
```
# WRONG (HTML)
https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/

# CORRECT (Markdown)
https://developers.cloudflare.com/durable-objects/best-practices/rules-of-durable-objects/index.md
```

Append `index.md` to any Cloudflare docs URL for clean Markdown.

## Handling Results

1. **Extract key patterns** from highlights
2. **Verify with multiple sources** when possible
3. **Note contradictions** if sources disagree
4. **Provide code snippets** when relevant
5. **Cite sources** with URLs

## Common Mistakes to Avoid

- ❌ Generic queries ("React best practices")
- ❌ Too few results for complex topics
- ❌ Ignoring domain filters (getting StackOverflow instead of docs)
- ❌ Fetching HTML when Markdown available (Cloudflare docs → append `/index.md`)
- ✅ Specific queries with versions and context
- ✅ Multiple queries for different aspects of the same topic
- ✅ Use domain filters to get authoritative sources
- ✅ Use Markdown endpoints for docs (Cloudflare docs, GitHub READMEs)

## Deep Research Workflow

For comprehensive research:

1. **Discovery query**: Broad search to find key sources
2. **Deeper queries**: Specific aspects found in discovery
3. **Verification**: Cross-reference findings
4. **Synthesis**: Combine into coherent answer

```
Query 1: "React 19 use() hook patterns"
  → Found official docs, blog post with production examples

Query 2: "use() hook promise caching"
  → Found GitHub issues, performance considerations

Query 3: "use() vs TanStack Query"
  → Found comparison table, when to use each
```

## Cost Considerations

- `numResults` affects cost linearly
- `deep` search is more expensive than `auto`
- `highlightsMaxCharacters` affects response size
- Start with 10 results, increase only if needed
