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

## Core Workflow

```
1. playwright-cli open
2. playwright-cli goto <url>
3. playwright-cli snapshot          # Get element refs (e0, e1, e2, ...)
4. playwright-cli click e15         # Use refs from snapshot
5. playwright-cli snapshot          # Refresh after DOM changes
6. playwright-cli type e20 "text"
7. playwright-cli screenshot        # Optional verification
8. playwright-cli close
```

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
# Mock API responses
playwright-cli route "*/api/*"
playwright-cli route-list
playwright-cli unroute "*/api/*"
```

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