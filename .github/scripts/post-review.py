#!/usr/bin/env python3
"""Post or update the Ollama Cloud review comment on a GitHub PR.

To avoid spamming the PR with a new comment on every push, this script
searches for a previously posted review comment (marked with a hidden
HTML marker) and updates it in place if found; otherwise it creates a
new comment.

Exit codes:
  0 = comment posted or updated
  1 = failure (error to stderr)

Environment variables:
  GITHUB_TOKEN              (required) Token with pull-requests: write
  GITHUB_REPOSITORY_OWNER   (required) Repository owner
  GITHUB_REPOSITORY_NAME    (required) Repository name
  PR_NUMBER                 (required) Pull request number
  REVIEW_TEXT               Review body text
  REVIEW_MODEL              Model name for the comment header
"""

import json
import os
import sys
import urllib.error
import urllib.request

# Hidden marker used to find this bot's own previous review comment
MARKER = "<!-- ollama-pr-review -->"
# GitHub rejects comment bodies > 65,536 chars; leave room for header/footer
MAX_BODY = 60000


def api(method, url, token, body=None):
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(
        url,
        data=data,
        method=method,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return resp.status, resp.read().decode("utf-8")


def main():
    review_text = os.environ.get("REVIEW_TEXT", "")
    model = os.environ.get("REVIEW_MODEL", "kimi-k3:cloud")
    token = os.environ.get("GITHUB_TOKEN", "")
    owner = os.environ.get("GITHUB_REPOSITORY_OWNER", "")
    repo = os.environ.get("GITHUB_REPOSITORY_NAME", "")
    pr_number = os.environ.get("PR_NUMBER", "")

    if not all([token, owner, repo, pr_number]):
        print("ERROR: Missing required environment variables", file=sys.stderr)
        sys.exit(1)

    if not review_text.strip():
        print("ERROR: REVIEW_TEXT is empty", file=sys.stderr)
        sys.exit(1)

    # Cap body length to stay under GitHub's 65,536-char limit (HTTP 422 above)
    if len(review_text) > MAX_BODY:
        review_text = review_text[:MAX_BODY] + "\n\n…(review truncated for length)"

    body_text = (
        f"{MARKER}\n"
        f"## 🤖 Ollama Cloud PR Review (Model: {model})\n\n"
        f"{review_text}\n\n"
        "---\n"
        "*Automated review by Ollama Cloud. The diff is untrusted input; "
        "findings may be inaccurate. If this review seems wrong, please "
        "provide feedback.*"
    )

    base = f"https://api.github.com/repos/{owner}/{repo}"
    comments_url = f"{base}/issues/{pr_number}/comments"
    payload = {"body": body_text}

    # Search for a previous review comment to update (first 100 comments)
    existing_id = None
    try:
        _, raw = api("GET", f"{comments_url}?per_page=100", token)
        for comment in json.loads(raw):
            if MARKER in (comment.get("body") or ""):
                existing_id = comment.get("id")
                break
    except Exception as e:
        # Search failure is non-fatal: fall back to creating a new comment
        print(f"WARN: could not search existing comments: {e}", file=sys.stderr)

    if existing_id:
        try:
            status, _ = api(
                "PATCH", f"{base}/issues/comments/{existing_id}", token, payload
            )
            print(f"updated existing comment ({status})")
            sys.exit(0)
        except urllib.error.HTTPError as e:
            detail = e.read().decode("utf-8", errors="replace")[:500]
            print(
                f"WARN: update failed (HTTP {e.code}): {detail} - creating new comment",
                file=sys.stderr,
            )
        except Exception as e:
            print(f"WARN: update failed: {e} - creating new comment", file=sys.stderr)

    try:
        status, _ = api("POST", comments_url, token, payload)
        print(f"created new comment ({status})")
        sys.exit(0)
    except urllib.error.HTTPError as e:
        detail = e.read().decode("utf-8", errors="replace")[:500]
        print(f"HTTP_ERROR: {e.code}: {detail}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"REQUEST_ERROR: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()