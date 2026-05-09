---
name: playwright-e2e
description: Write and run end-to-end Playwright tests to validate frontend UI changes — mock the API, drive the browser, assert what the user would see.
argument-hint: "[test-file-glob or --new <name>]"
allowed-tools: Read Edit Write Bash Grep Glob
---

# Playwright E2E

Use this when you need real-browser proof that a UI change works end-to-end and clicking through manually is not an option (you're a CLI agent).

The pattern is: **mock the API, drive the browser, assert what the user would see.** The dev server boots automatically; tests run in 10–30s; you get screenshots on failure to diagnose.

## Step 1: Detect the project's Playwright setup

Find the existing config and test directory. Most repos have one. Don't reinvent it.

```bash
fd -t f 'playwright.config.(ts|js|mjs)' --max-depth 3 2>/dev/null \
  || find . -maxdepth 4 -name 'playwright.config.*' -not -path '*/node_modules/*' 2>/dev/null
```

Read the config to learn:
- `testDir` — where tests live
- `webServer.command` — what auto-starts the dev server (and on what port)
- `use.baseURL` — the URL tests target
- Any existing helpers in the test directory

If there's no Playwright setup yet, fall back to **Step 1b**.

### Step 1b: Bootstrap Playwright in a project that doesn't have it

```bash
# Most repos: install in the test package, not root
pnpm --filter <test-pkg> add -D @playwright/test
pnpm exec playwright install chromium
```

Create a minimal `playwright.config.ts` mirroring the project's dev-server command. Use the existing `package.json` `dev` script.

## Step 2: Read an existing test for patterns

The most valuable thing you can do before writing a new test is **steal patterns from an existing one in the same repo**. Specifically extract:

- How the project mocks API routes (`page.route` + `route.fulfill`)
- How it mocks auth/session (cookies vs `auth/me` JSON)
- How it tracks runtime errors (console listener, page error handler)
- The `failUnexpectedApi` pattern — fails the test if any unmocked API request escapes (catches missing mocks early)
- Helper functions for common fixtures

```bash
# Find tests with mock patterns and read the most recent one
rg -l 'page\.route|route\.fulfill' tests/ apps/*/tests/ 2>/dev/null | head -3 | xargs -I {} bash -c 'echo "=== {} ==="; head -120 "{}"'
```

## Step 3: Write a focused test for the change

**Scope rule:** one describe block, 2–6 tests. Each test exercises one user-visible flow.

Structure each test as:

```ts
test("user-visible behavior in plain English", async ({ page }) => {
  // 1. Mock all APIs the page will hit
  await mockSession(page);
  await mockJson(page, "/api/v1/...", fixture);

  // 2. Mock the mutation under test, capture that it fired
  let endpointCalled = false;
  await page.route(`${API_URL}/api/v1/things/restart`, async (route) => {
    endpointCalled = true;
    await route.fulfill({ status: 200, contentType: "application/json", body: "{}" });
  });

  // 3. Navigate
  await page.goto(`${UI_URL}/portal/things/1?api=${encodeURIComponent(API_URL)}`);

  // 4. Drive: prefer getByRole > getByText > CSS selectors
  await page.getByRole("tab", { name: "Settings" }).click();
  await page.getByRole("button", { name: "Restart" }).click();

  // 5. Assert what the user sees
  const modal = page.getByRole("dialog");
  await expect(modal).toBeVisible();
  await modal.getByRole("button", { name: "Restart" }).click();

  await expect(page.getByText("Restart sent")).toBeVisible({ timeout: 5000 });
  expect(endpointCalled).toBe(true);
});
```

### Selector preference (in this order)

1. **`getByRole`** — most accessible and stable. `{ name: "..." }` matches accessible name (button text, aria-label).
2. **`getByText`** — for plain text content. Use regex for fuzzy: `getByText(/Send a Restart command/)`.
3. **`getByLabel`** / **`getByPlaceholder`** — for form fields.
4. **`page.locator('[data-testid=...]')`** — last resort. Add `data-testid` to the component if nothing else works.
5. **CSS selectors** — never. Brittle.

### Common gotchas

- **Modals/dialogs:** scope assertions to the modal: `const modal = page.getByRole("dialog"); await modal.getByRole("button", ...)`. Otherwise duplicate buttons (e.g. "Restart" both as the trigger and inside the modal) fail with strict-mode violation.
- **Mantine notifications:** they render in a portal at the document root. Assert with `page.getByText(...)`, not `modal.getByText(...)`.
- **Mantine Modal autofocus:** `data-autofocus`, not `autoFocus`. The HTML attribute silently fails inside the focus trap.
- **Field name mismatches in fixtures:** if a test fails with the page rendering a "not connected" / "no data" state, re-read the page model — your fixture probably uses `isConnected` (camelCase) but the model expects `is_connected` (snake_case API contract). Fixtures must match the API shape, not the React state shape.
- **Async fields like `query.data` arriving late:** wrap navigation with `await page.waitForLoadState("networkidle")` only if you see flakiness; usually `expect(...).toBeVisible({ timeout: ... })` is enough.
- **Loading-toast morph:** if the toast morphs from loading → success too fast for your assertion, add a small `await page.waitForTimeout(N)` in the mocked endpoint to slow the response, OR assert the success state directly (Mantine updates atomically by id).

## Step 4: Run the tests

```bash
# From the test package directory
pnpm exec playwright test <pattern> --reporter=list

# Headed (browser visible) — for debugging or showing the user
pnpm exec playwright test <pattern> --headed

# UI mode — interactive, time-travel debugger
pnpm exec playwright test <pattern> --ui
```

The webServer in `playwright.config.ts` will auto-start the dev server. First run takes ~30s for the server to come up; subsequent runs reuse it (`reuseExistingServer: true`).

## Step 5: Diagnose failures

On failure, Playwright drops:

- **`test-results/<test-name>/test-failed-1.png`** — screenshot at moment of failure
- **`test-results/<test-name>/error-context.md`** — DOM snapshot
- **`test-results/<test-name>-retry1/trace.zip`** — full trace including network, console, DOM snapshots over time

Read the screenshot first (`Read` tool — Playwright PNGs work). The DOM snapshot is the second-best diagnostic. Use the trace for timing-sensitive bugs:

```bash
pnpm exec playwright show-trace test-results/<dir>/trace.zip
```

The error log usually pinpoints:
- A locator that resolved to a different element than expected (look at the locator's "received" attributes — `disabled="true"`, wrong text, etc.)
- A locator that timed out (the element never appeared — fixture data wrong, route not mocked, page broken)
- A strict-mode violation (multiple elements match — scope to a parent)

## Step 6: Report results back

Tell the user:
- Which flows are validated (each test in plain English)
- Which mocks were used (so they know what's NOT validated against a real backend)
- Anything that still requires human verification (visual polish, accessibility, real-data flows)

## Notes

- **Scope:** these tests prove behavior at the UI/API contract boundary. They do NOT prove the backend works correctly with real data. Pair with integration tests against a real worker for full confidence.
- **Idempotency:** `page.route` mocks reset per-test. Use `test.beforeEach` for shared mocks (session, guidance).
- **Cost:** each test costs ~2–10 seconds wall clock. Don't run hundreds; pick the 2–6 highest-value flows per change.
- **Don't bypass:** if the existing project has a `failUnexpectedApi` pattern, keep it. It catches "I forgot to mock that endpoint" bugs early instead of letting tests pass with silent network failures.
