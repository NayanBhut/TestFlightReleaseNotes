# PR Review — Test Scenarios & Failure Guide

This document describes every test scenario built into the CI workflow and how to fix common failures.

---

## Workflow Jobs Overview

| Job | Trigger | Purpose |
|-----|---------|---------|
| `build` | Push / PR | Build the Swift project (existing) |
| `pr-review` | PR only | Ollama Cloud review with 5 test checkpoints |
| `review-report` | PR only | Summarize results + troubleshooting guide |
| `smoke-test` | PR title contains `[smoke-test]` | Quick one-step API connectivity check |

---

## Test Scenarios (inside `pr-review` job)

### Test 1 — Ollama Cloud Auth Check (zero tokens)

**What it does:** Verifies your API key is valid WITHOUT generating tokens. It sends an empty-payload POST to `/v1/chat/completions`: a valid key gets HTTP 400 (payload rejected before any generation), a bad key gets 401/403.

**What a pass looks like:**
```
✅ PASS: Ollama Cloud auth OK (HTTP 400, zero tokens used)
```

**What a failure looks like:**
```
❌ FAIL: OLLAMA_API_KEY is not set in repository secrets.
❌ FAIL: API key rejected (HTTP 401)
❌ FAIL: API key rejected (HTTP 403)
```

**How to fix:**
1. Go to **Settings → Secrets and variables → Actions** in your GitHub repo
2. Click **New repository secret**
3. Name: `OLLAMA_API_KEY`
4. Value: Your Ollama Cloud API key (get one at https://ollama.com)
5. Re-run the PR check

---

### Test 2 — Model Availability Check (zero tokens)

**What it does:** Verifies the configured model exists on Ollama Cloud by checking the free `/v1/models` catalog — no paid generation. The model is configured once via the `OLLAMA_MODEL` env var at the top of the workflow.

**What a pass looks like:**
```
✅ PASS: Model 'kimi-k3:cloud' is available
```

**What a failure looks like:**
```
❌ FAIL: Model 'kimi-k3:cloud' not found in the Ollama Cloud catalog
❌ FAIL: Could not fetch model catalog (HTTP 500)
```

**How to fix:**
1. Check available models at https://ollama.com/library
2. Update `OLLAMA_MODEL` in the `env:` block at the top of `.github/workflows/Build.yml`

---

### Test 3 — GitHub Token Write Check

**What it does:** REALLY verifies the token can post comments. A plain GET succeeds with read-only permissions and gives false confidence, so this test creates a temporary probe comment and immediately deletes it — proving actual write access.

**What a pass looks like:**
```
✅ PASS: Token write access confirmed (ok)
```

**What a failure looks like:**
```
❌ FAIL: Token cannot post comments
Details: CREATE_FAILED: HTTP 403 - token cannot post comments. Ensure 'pull-requests: write' is in the job permissions.
```

**How to fix:**
1. Open `.github/workflows/Build.yml`
2. In the `pr-review` job, ensure permissions include:
   ```yaml
   permissions:
     contents: read
     pull-requests: write
   ```
3. If using a fork PR, the built-in `GITHUB_TOKEN` cannot write to forks. Use a PAT with repo permissions:
   - Create a PAT at https://github.com/settings/tokens
   - Add it as secret `MY_GITHUB_TOKEN`
   - Use it in place of `${{ secrets.GITHUB_TOKEN }}`

---

### Test 4 — PR Diff Fetch Check

**What it does:** Makes sure the PR changes are accessible and downloadable.

**What a pass looks like:**
```
✅ PASS: PR diff is accessible
```

**What a failure looks like:**
```
❌ FAIL: Cannot fetch PR diff (HTTP 404)
❌ FAIL: Cannot fetch PR diff (HTTP 403)
```

**How to fix:**
- **HTTP 404**: PR doesn't exist or is already merged/closed
- **HTTP 403**: Fork PR without `contents: read` permission. Add to workflow:
  ```yaml
  permissions:
    contents: read
  ```
- PR has only metadata changes (title edit, label change) — review will be skipped gracefully

---

### Test 5 — Review Comment Validation

**What it does:** After posting the review, verifies the comment actually appears on the PR. Only runs when a review was actually posted (`success == 'yes'`) — running after skips/failures would only emit confusing warnings.

**What a pass looks like:**
```
✅ PASS: Review comment verified on PR
```

**What a failure looks like:**
```
⚠️ WARN: Could not verify review comment on PR
```

**How to fix:**
- Usually a timing issue; the comment may still appear
- Check the "Review Comment Validation" step logs
- Manually check the PR for the posted comment

---

## Test 6 — Post-Review Result (in `review-report` job)

**What it does:** Prints a summary table and troubleshooting guide.

**Example output when all tests pass:**
```
═══════════════════════════════════════════════════════════
         PR REVIEW TEST SCENARIOS REPORT
═══════════════════════════════════════════════════════════

Test Scenario                        | Status
─────────────────────────────────────|───────────────
1. Ollama Cloud Connectivity         | ✅ PASS
2. Model Availability               | ✅ PASS
3. GitHub Token Permissions          | Check logs
4. PR Diff Accessibility             | Check logs
5. Review Comment Validation         | Check logs

Review Result: yes
Model Used: kimi-k3:cloud
═══════════════════════════════════════════════════════════
```

**Example output when tests fail:**
The `review-report` job automatically prints a troubleshooting guide with specific fix instructions for each failed test.

---

## Smoke Test (Manual)

To quickly test Ollama Cloud without posting a review, create a PR with `[smoke-test]` anywhere in the title:

```
Title: [smoke-test] quick connectivity check
```

This runs a minimal API call and reports success/failure without posting any review comments.

**Skipping the review:** Add `[skip-review]` anywhere in the PR title and the LLM review job is skipped entirely (the Swift build still runs).

---

## Common Issues Quick Reference

| Error/Symptom | Cause | Fix |
|---------------|-------|-----|
| `OLLAMA_API_KEY is not set` | Missing secret | Add secret in repo Settings |
| `HTTP 401 from Ollama` | Invalid API key | Regenerate key at ollama.com |
| `Model not found` | Model unavailable | Check ollama.com/library; pick another |
| `HTTP 403 from GitHub` | Token lacks permissions | Add `pull-requests: write` to permissions |
| `Cannot fetch PR diff` | Fork without access | Add `contents: read`; or use PAT |
| `No diff found` | Binary-only PR | Review is skipped; add text changes |
| `Review took too long` | Model too large | Use smaller model (e.g., `qwen2.5-coder:7b`) |
| `Rate limit exceeded` | Too many API calls | Wait and re-trigger; check usage dashboard |
| `Empty review response` | Model hallucination | Adjust prompt; try different model |

---

## Checking Workflow Results

### On the PR page:
1. Go to your PR → Click **Checks** tab
2. Look for:
   - ✅ **Build** — Swift compilation status
   - 🤖 **PR Review** — Ollama review with 5 test steps
   - 📊 **Review Report** — Summary table

### On the Actions page:
1. Go to repository → **Actions** tab
2. Click on the workflow run for your PR
3. Expand each step to see detailed output
4. Failed steps show error messages with fix instructions

### Checking Ollama Cloud usage:
1. Visit https://ollama.com/account
2. Check your API usage and rate limits
3. Verify your key hasn't expired
