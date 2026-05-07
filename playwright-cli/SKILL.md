---
name: playwright-cli
description: Automate browser interactions using Microsoft's playwright-cli. Uses snapshot-first workflow with element references instead of CSS selectors. Use when the user says "browser automation", "interact with a page", "test a web page", or "fill out a form".
allowed-tools: Bash
---

# Browser Automation with playwright-cli

## What is playwright-cli?

`playwright-cli` is Microsoft's **[@playwright/cli](https://github.com/microsoft/playwright-cli)** package. Unlike raw Playwright scripts that use CSS/XPath selectors, it uses **element snapshots** with stable references like `e15`.

### Why snapshot-first is better for agents

| Raw Playwright | playwright-cli |
|---------------|---------------|
| `page.click("#submit-btn")` | `playwright-cli click e15` |
| Selectors break when DOM changes | References persist across DOM mutations |
| Need to wait for selectors | Snapshot already resolves elements |
| CSS selectors are fragile | Element refs are stable and semantic |

The snapshot gives you element references that remain valid even if JavaScript rewrites the DOM. This makes browser automation **reliable** rather than flaky.

## When to use this vs. `playwright-e2e`

| Use `playwright-cli` for                                   | Use `playwright-e2e` for                                          |
| ---------------------------------------------------------- | ----------------------------------------------------------------- |
| One-off interactive verification of a UI change            | Repeatable automated checks that run in CI                        |
| Debugging why a Playwright test is flaky                   | Asserting a specific user-visible behavior                        |
| Showing the user what a flow looks like (snapshots/PNGs)   | Per-test scoped mocks, parallel execution                         |
| Exploratory poking around an unfamiliar app                | Declarative assertions (`toBeVisible`, `toBeEnabled`)             |

`playwright-cli` is **imperative and exploratory** — you read snapshots and verify by eye. There are no built-in assertions; success means "the snapshot looks right." For durable tests that fail loudly when behavior breaks, write `@playwright/test` cases instead (the `playwright-e2e` skill walks through that path).

## Core Workflow

```
1. playwright-cli open
2. playwright-cli route "**/auth/me" --body '{"user":...}'    # Mock BEFORE goto
3. playwright-cli route "**/api/v1/..." --body '...'
4. playwright-cli goto <url>
5. playwright-cli snapshot          # Get element refs (e0, e1, e2, ...)
6. playwright-cli click e15         # Use refs from snapshot
7. playwright-cli snapshot          # Refresh after DOM changes
8. playwright-cli type e20 "text"
9. playwright-cli screenshot        # Optional verification
10. playwright-cli close
```

> **Critical: register mocks BEFORE the first `goto`.** Any auth-protected SPA (almost all of them) hits `/auth/me` or similar on first paint. If that returns 500/401 because no mock is registered yet, the page redirects to `/login` and your subsequent `goto` to a deep link silently fails. **Open → mocks → goto** is the only order that works.

## Quick start

```bash
# Open browser
playwright-cli open

# Navigate
playwright-cli goto https://example.com

# Get element references
playwright-cli snapshot
# Output shows refs like:
#   e0: button "Submit"
#   e1: input[type="text"][name="email"]
#   e2: input[type="password"][name="password"]

# Interact using refs
playwright-cli fill e1 "user@example.com"
playwright-cli fill e2 "password123"
playwright-cli click e0

# Verify
playwright-cli snapshot  # Get new refs after page change
playwright-cli screenshot
```

## Commands

### Core

```bash
playwright-cli open                              # Open browser
playwright-cli open https://example.com/         # Open and navigate
playwright-cli goto <url>                       # Navigate
playwright-cli snapshot [element]                # Get element refs
playwright-cli click <ref> [button]            # Click (left/right/middle)
playwright-cli dblclick <ref>                   # Double click
playwright-cli fill <ref> <text> [--submit]    # Fill and optionally submit
playwright-cli type <ref> <text>               # Type character by character
playwright-cli hover <ref>                      # Hover
playwright-cli select <ref> <value>            # Select dropdown option
playwright-cli check <ref>                      # Check checkbox/radio
playwright-cli uncheck <ref>                    # Uncheck
playwright-cli drag <start_ref> <end_ref>       # Drag and drop
playwright-cli upload <ref> <file>              # Upload file
```

### Element References

After `snapshot`, elements are referenced by ID:
```
e0: button "Submit"
e1: input[type="text"][name="email"]
e2: input[type="password"][name="password"]
e3: a[href="/forgot"]
```

Use these refs directly in commands:
```bash
playwright-cli fill e1 "user@example.com"
playwright-cli click e0
```

### Evaluation

```bash
# Evaluate JavaScript on page
playwright-cli eval "document.title"
playwright-cli eval "el => el.textContent" e5
playwright-cli eval "el => el.id" e5
playwright-cli eval "el => el.getAttribute('data-testid')" e5
```

### Navigation

```bash
playwright-cli go-back
playwright-cli go-forward
playwright-cli reload
```

### Keyboard

```bash
playwright-cli press Enter
playwright-cli press ArrowDown
playwright-cli keydown Shift
playwright-cli keyup Shift
```

### Mouse

```bash
playwright-cli mousemove 150 300
playwright-cli mousedown
playwright-cli mouseup
playwright-cli mousewheel 0 100
```

### Screenshot/PDF

```bash
playwright-cli screenshot              # Full page
playwright-cli screenshot e5         # Specific element
playwright-cli pdf
```

### Tabs

```bash
playwright-cli tab-list              # List all tabs
playwright-cli tab-new <url>         # Open new tab
playwright-cli tab-close             # Close current tab
playwright-cli tab-select <index>   # Switch to tab
```

### Storage (Auth, Cookies)

```bash
# Save/restore authentication state
playwright-cli state-save auth.json
playwright-cli state-load auth.json

# Cookies
playwright-cli cookie-list
playwright-cli cookie-set name value
playwright-cli cookie-delete name
playwright-cli cookie-clear
```

### Network Mocking

```bash
# Mock with full response control
playwright-cli route "**/api/v1/users" \
  --status 200 \
  --content-type "application/json" \
  --body '{"users":[]}'

# Mock with headers
playwright-cli route "**/api/v1/secret" \
  --status 200 \
  --body 'ok' \
  --header "X-Foo: bar"

# Glob patterns: ** matches any path, * matches a single segment
# Always quote glob patterns to keep the shell from expanding them.
playwright-cli route "**/api/v1/things/*/status" --body '{"healthy":true}'

# Manage routes
playwright-cli route-list
playwright-cli unroute "**/api/*"
```

**Body escaping.** For inline JSON, single-quote the whole `--body` value so the shell doesn't expand `$` or quotes:

```bash
playwright-cli route "**/api/me" --body '{"user":{"id":"u1","email":"x@y.z"}}'
```

For larger fixtures, read from a file — the shell expands `$(cat …)` before passing to `playwright-cli`:

```bash
playwright-cli route "**/api/things" --body "$(cat fixtures/things.json)"
```

**Mock order matters.** Mocks are first-match. Register more-specific patterns first (e.g. `**/api/v1/things/123` before `**/api/v1/things/*`).

### Sessions

```bash
# Named sessions (attach to existing browser)
playwright-cli -s=my-session open

# List sessions
playwright-cli list

# Clean up
playwright-cli close
playwright-cli close-all
playwright-cli kill-all
```

### DevTools

```bash
playwright-cli console [min-level]  # View console logs
playwright-cli network              # View network requests
playwright-cli tracing-start
playwright-cli tracing-stop
playwright-cli show                  # Open DevTools
```

## Browser Options

```bash
--browser=chrome    # Chrome (default)
--browser=firefox   # Firefox
--browser=webkit    # WebKit
--browser=msedge    # Microsoft Edge
--headed            # Show browser window
```

## Why playwright-cli beats raw Playwright scripts

1. **Stable refs**: CSS selectors break when developers refactor HTML. Element refs from snapshots are semantic and stable.

2. **Snapshot shows actual state**: The snapshot reflects what's actually rendered, not what selectors *expect* to exist.

3. **Agents don't need to write selectors**: Agents get refs directly and use them. No selector debugging.

4. **Session persistence**: State carries across commands. Login persists. No need to re-authenticate.

5. **Network mocking built-in**: Route API calls without writing server stubs.

6. **Storage API**: Save/restore cookies and localStorage for authenticated sessions.

## Example: Login Flow

```bash
playwright-cli open
playwright-cli goto https://app.example.com/login
playwright-cli snapshot

# Output:
# e0: input[type="text"][name="username"]
# e1: input[type="password"][name="password"]
# e2: button[type="submit"]

playwright-cli fill e0 "myuser"
playwright-cli fill e1 "mypassword"
playwright-cli click e2

playwright-cli snapshot
# Now on dashboard
playwright-cli screenshot
```

## Recipe: Verifying an authenticated SPA deep-link (mocked)

The most common use case: an authenticated single-page app where you want to verify a specific page's behavior without spinning up the full backend. The trick is **mock everything the page hits before the first `goto`** — otherwise the auth check fails and the SPA bounces to `/login`.

```bash
SESSION=demo

# 1. Open
playwright-cli -s=$SESSION open

# 2. Mock auth + initial data BEFORE any navigation
playwright-cli -s=$SESSION route "**/auth/me" \
  --status 200 --content-type "application/json" \
  --body '{"user":{"userId":"u1","email":"x@y.z","role":"member","tenantId":"t1"}}'

playwright-cli -s=$SESSION route "**/api/v1/tenant" \
  --body '{"id":"t1","name":"Demo","plan":"pro"}'

playwright-cli -s=$SESSION route "**/api/v1/things/123" \
  --body "$(cat fixtures/thing-123.json)"

# 3. Now navigate
playwright-cli -s=$SESSION goto http://localhost:3000/things/123

# 4. Snapshot to find element refs
playwright-cli -s=$SESSION snapshot

# 5. Drive
playwright-cli -s=$SESSION click e164      # Settings tab
playwright-cli -s=$SESSION click e239      # "Restart" button

# 6. Mock the mutation just before triggering it
playwright-cli -s=$SESSION route "**/api/v1/things/123/restart" \
  --body '{"restarted":2}'

playwright-cli -s=$SESSION snapshot        # confirm modal opened
playwright-cli -s=$SESSION click e276      # confirm button
playwright-cli -s=$SESSION snapshot        # toast should now show
playwright-cli -s=$SESSION screenshot      # visual proof

# 7. Inspect what the SPA actually hit
playwright-cli -s=$SESSION network         # see all requests
playwright-cli -s=$SESSION console         # see any errors

# 8. Clean up
playwright-cli -s=$SESSION close
```

**Why this works:** every API request the SPA makes is intercepted by a registered route. None of the requests hit a real backend, so the worker/server doesn't need to be running. The `failUnexpectedApi`-style "fail on unmocked routes" pattern from `@playwright/test` doesn't exist in `playwright-cli` — instead, watch `playwright-cli network` for unmocked URLs.

## Limitations & gotchas

- **No built-in assertions.** `playwright-cli` is for *exploration* and *visual verification*. There's no `expect(...).toBeVisible()`. You read snapshots and PNGs and judge by eye. If you need pass/fail in CI, write `@playwright/test` cases (see the `playwright-e2e` skill).
- **Each command is a fresh Node process.** Chaining 10 commands costs ~10× process-spawn overhead. Snapshots and `route` registrations persist across commands within the same `-s=<session>`, but the latency adds up — for tight loops the test runner is much faster.
- **Element refs (`e15`) live inside one snapshot.** When the page DOM changes (new modal, route change), call `snapshot` again to get fresh refs. Existing refs may still resolve if the underlying element stuck around, but don't count on it across major React re-renders.
- **Mock-before-`goto` is mandatory for auth-protected SPAs.** First-paint requests fire the moment the page loads. Register `**/auth/me` (or your equivalent) and any data the page reads before route changes settle, *before* you call `goto`.
- **Glob quoting matters.** Always wrap patterns in single or double quotes — bare `**` and `*` will be expanded by the shell. `route "**/api/*"` is safe; `route **/api/*` will silently match files in your CWD instead.
- **Session is the persistence boundary.** Mocks, cookies, and tabs all attach to a session (`-s=name`). Forget the flag and you'll get a fresh browser without your mocks. Pick a session name and use it consistently.
- **`route-list` shows what's registered, `network` shows what fired.** Use them together: `route-list` confirms your mocks landed; `network` confirms the page hit them (or fell through to a real request).