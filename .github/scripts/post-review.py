#!/usr/bin/env python3
"""Post a review comment to a GitHub PR."""

import json
import os
import sys
import urllib.request
import urllib.error


def main():
    review_text = os.environ.get("REVIEW_TEXT", "")
    model = os.environ.get("REVIEW_MODEL", "kimi-k3:cloud")
    token = os.environ.get("GITHUB_TOKEN", "")
    owner = os.environ.get("GITHUB_REPOSITORY_OWNER", "")
    repo = os.environ.get("GITHUB_REPOSITORY_NAME", "")
    pr_number = os.environ.get("PR_NUMBER", "")

    if not token:
        print("ERROR: GITHUB_TOKEN not set", file=sys.stderr)
        sys.exit(1)
    if not owner or not repo or not pr_number:
        print("ERROR: Missing GitHub repo/PR info", file=sys.stderr)
        sys.exit(1)

    body = json.dumps({
        "body": (
            f"## 🤖 Ollama Cloud PR Review (Model: {model})\n\n"
            f"{review_text}\n\n"
            "---\n"
            "*Automated review by Ollama Cloud. If this review seems inaccurate, please provide feedback.*"
        )
    }).encode("utf-8")

    url = f"https://api.github.com/repos/{owner}/{repo}/issues/{pr_number}/comments"

    req = urllib.request.Request(
        url,
        data=body,
        method="POST",
        headers={
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "Accept": "application/vnd.github.v3+json",
        },
    )

    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            print(str(resp.status))
    except urllib.error.HTTPError as e:
        print(f"HTTP_ERROR: {e.code}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"REQUEST_ERROR: {str(e)}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
