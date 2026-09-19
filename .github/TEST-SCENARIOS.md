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

### Test 1 — Ollama Cloud Connectivity Check

**What it does:** Verifies the Ollama Cloud API endpoint is reachable and your API key is valid.

**What a pass looks like:**
```
✅ PASS: Ollama Cloud API is reachable (HTTP 200)
```

**What a failure looks like:**
```
❌ FAIL: OLLAMA_API_KEY is not set in repository secrets.
❌ FAIL: Ollama Cloud API returned HTTP 401
❌ FAIL: Ollama Cloud API returned HTTP 403
```

**How to fix:**
1. Go to **Settings → Secrets and variables → Actions** in your GitHub repo
2. Click **New repository secret**
3. Name: `OLLAMA_API_KEY`
4. Value: Your Ollama Cloud API key (get one at https://ollama.com)
5. Re-run the PR check

---

### Test 2 — Model Availability Check

**What it does:** Checks that the configured model (`kimi-k3:cloud`) is available on Ollama Cloud. Falls back to `qwen2.5-coder:7b` if unavailable.

**What a pass looks like:**
```
✅ PASS: Model 'kimi-k3:cloud' is available
✅ PASS: Fallback model 'qwen2.5-coder:7b' is available
```

**What a failure looks like:**
```
❌ FAIL: Both models unavailable.
⚠️ Model 'kimi-k3:cloud' not found.
```

**How to fix:**
1. Visit the model library: https://ollama.com/library/kimi-k3
2. Find a model that supports **chat** completions (not just completion)
3. Update the `MODEL` value in `.github/workflows/Build.yml`
4. Recommended models for code review:
   - `kimi-k3:cloud` (best, Moonshot AI)
   - `qwen2.5-coder:7b` (lightweight)
   - `llama3.3`
   - `deepseek-r1:70b`

---

### Test 3 — GitHub Token Permission Check

**What it does:** Verifies the GitHub token can post comments on the PR.

**What a pass looks like:**
```
✅ PASS: GitHub token can post PR comments
```

**What a failure looks like:**
```
❌ FAIL: GitHub token cannot post comments (HTTP 403)
❌ FAIL: GitHub token cannot post comments (HTTP 401)
```

**How to fix:**
1. Open `.github/workflows/Build.yml`
2. In the `pr-review` job, ensure permissions include:
   ```yaml
   permissions:
     contents: read
     pull-requests: write
     id-token: write
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

**What it does:** After posting the review, verifies the comment actually appears on the PR.

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

To quickly test Ollama Cloud without posting a review, create a PR with `[smoke-test]` in the title:

```
Title: [smoke-test] quick connectivity check
```

This runs a minimal API call and reports success/failure without posting any comments.

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
